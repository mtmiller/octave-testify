## Copyright (C) 2019 Andrew Janke
##
## This file is part of Octave.
##
## Octave is free software: you can redistribute it and/or modify it
## under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## Octave is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with Octave; see the file COPYING.  If not, see
## <https://www.gnu.org/licenses/>.

classdef MultiBistRunner < handle
  %MULTIBISTRUNNER Runs BISTs for multiple source files
  %
  % This knows how to locate multiple files that contain tests, run them using
  % BistRunner, and format output in a higher-level multi-file manner.
  % 
  % This is basically the implementation for the runtests2() function.
  %
  % TODO: To reproduce runtests2's output, we need to track tagged groups of test
  % files, not just individual files, so we can do the "Processing files in <dir>:"
  % outputs.
  %
  % The add_* functions add things to the test file sets.
  % The search_* functions return lists of files for identified things.

  properties
    % List of files to test, as { tag, files; ... }. Paths in files may be absolute
    % or relative.
    files = cell (0, 2)
    % Extensions for files that might contain tests
    test_file_extensions = {'.m', '.cc', '.cc-tst', '.tst'}
    % Control for shuffling test file order. true/false/double
    shuffle = false;
    % Whether to abort on test failure
    fail_fast = false;
    % Whether to save out copies of the workspace upon test failure
    save_workspace_on_failure = false;
    % File handle to log low-level output to
    log_fid = []
  endproperties

  methods

    function this = MultiBistRunner (log_fid)
      if nargin == 0
        return
      endif
      this.log_fid = log_fid;
    endfunction

    function add_file_or_directory (this, file, tag)
      if nargin < 3 || isempty (tag); tag = file; end
      if isfolder (file)
        this.add_directory (file, tag);
      else
        this.add_file (file, tag);
      endif
    endfunction

    function add_target_auto (this, target, tag)
      % Add a specified test target, inferring its type from its value
      %
      % Right now, this only supports files and dirs
      if nargin < 3 || isempty (tag); tag = target; end

      if ! ischar (target)
        error ("MultiBistRunner.add_target_auto: target must be char; got %s", class (target));
      endif

      # File or dir?
      canon_path = canonicalize_file_name (target);
      if ! isempty (canon_path) &&  exist (canon_path, "dir")
        this.add_directory (canon_path, tag);
        return
      elseif ! isempty (canon_path) && exist (canon_path, "file")
        this.add_file (canon_path, tag);
        return
      elseif exist (target, "dir")
        this.add_directory (target, tag);
        return
      elseif exist (target, "file")
        this.add_file (target, tag);
        return
      else
        # Search for dir on path
        f = target;
        if f(end) == '/' || f(end) == '\'
          f(end) = [];
        endif
        found_dir = dir_in_loadpath (f);
        if ! isempty (found_dir)
          this.add_directory (found_dir, tag);
          return
        endif
      endif

      # File glob?
      if any (target == "*")
        files = glob (target);
        if isempty (files)
          error ("File not found: %s", target);
        endif
        this.add_fileset (tag, files);
        return
      endif

      # Function? Class?
      if this.add_ns_qualified_function_or_class (target)
        return
      endif

      error ("MultiBistRunner: Could not resolve test target %s", target);
    endfunction

    function add_file (this, file, tag)
      if nargin < 3 || isempty (tag); tag = file; end
      if isfolder (file)
        error ("MultiBistRunner.add_file: file is a directory: %s", file);
      endif
      this.add_fileset (["file " tag], file);
    endfunction

    function add_directory (this, path, tag, recurse = true)
      if nargin < 3 || isempty (tag)
        tag = ["directory " path];
      end
      if ! isfolder (path)
        error ("MultiBistRunner.add_directory: not a directory: %s", path);
      endif

      files = this.search_directory (path, recurse);
      this.add_fileset (tag, files);
    endfunction

    function add_stuff_on_octave_search_path (this)
      dirs = ostrsplit (path (), pathsep ());
      tags = strrep(dirs, matlabroot, '<Octave>');
      for i = 1:numel (dirs)
        this.add_directory (dirs{i}, tags{i});
      endfor
    endfunction

    function out = search_directory (this, path, recurse = true)
      out = {};
      kids = setdiff (readdir (path), {".", ".."});
      for i = 1:numel (kids)
        f = fullfile (path, kids{i});
        if isfolder (f)
          if recurse
            out = [out this.search_directory(f, recurse)];
          endif
        else
          if this.looks_like_testable_file (f);
            out{end+1} = f;
          endif
        endif
      endfor
    endfunction

    function add_function (this, name)
      %TODO: Add support for namespaces. This will require doing our own path search,
      % because which() doesn't support them.
      fcn_file = this.search_function_file (name);
      if ! isempty (fcn_file)
        this.add_fileset (["function " name], fcn_file);
      endif
    endfunction

    function add_class (this, name)
      files = this.search_class_files (name);
      this.add_fileset (["class " name], files);
    endfunction

    function out = search_function_file (this, name)
      % We do this instead of which() because which() does not support namespaces
      ref = this.parse_namespaced_thing (name);
      identifier = ref.thing;
      if ref.is_namespaced
        ns_els = strsplit (ref.namespace, ".");
        ns_path = ["/" strjoin(strcat("+",ns_els), filesep) "/"];
      else
        ns_path = "";
      endif

      p = ostrsplit (path, pathsep, true);
      for i = 1:numel (p)
        dir = p{i};
        fcn_file = [dir ns_path [identifier ".m"]];
        if exist (fcn_file, "file")
          out = fcn_file;
          return;
        endif
      endfor

      out = [];
    end

    function out = search_class_files (this, name)
      % Finds all files in a class definition

      ref = this.parse_namespaced_thing (name);
      identifier = ref.thing;
      if ref.is_namespaced
        ns_els = strsplit (ref.namespace, ".");
        ns_path = ["/" strjoin(strcat("+",ns_els), filesep) "/"];
      else
        ns_path = "";
      endif

      out = {};
      p = ostrsplit (path, pathsep, true);
      for i = 1:numel (p)
        dir = p{i};
        classdef_file = [dir ns_path [identifier ".m"]];
        if exist (classdef_file, "file") && is_classdef_file (classdef_file)
          out{end+1} = classdef_file;
        endif
        atclass_dir = [dir ns_path ["@" identifier]];
        if exist (atclass_dir, "dir")
          atclass_files = this.search_directory (atclass_dir, true);
          out = [out atclass_files];
        endif
      endfor
    endfunction

    function out = add_ns_qualified_function_or_class (this, name)
      out = true;
      fcn_file = this.search_function_file (name);
      if ! isempty (fcn_file)
        this.add_function (name);
        return
      endif
      class_files = this.search_class_files (name);
      if ! isempty (class_files)
        this.add_class (name);
        return
      endif
      out = false;
    endfunction

    function out = looks_like_testable_file (this, file)
      out = endswith_any (file, this.test_file_extensions);
    endfunction

    function add_package (this, name)
      info = pkg ("list", name);
      info = info{1};
      if isempty(info)
        error ("package '%s' is not installed", name);
      endif
      files = this.search_directory (info.dir);
      % TODO: Do we need to separately search through archprefix here?
      this.add_fileset (["package " name], files);
    endfunction

    function add_installed_packages (this)
      pkgs = pkg ("list");
      for i = 1:numel (pkgs)
        this.add_package (pkgs{i}.name);
      endfor
    endfunction

    function add_octave_builtins (this)
      % Add the tests for all the Octave builtins
      testsdir = __octave_config_info__ ("octtestsdir");
      libinterptestdir = fullfile (testsdir, "libinterp");
      this.add_directory (libinterptestdir, "Octave builtins: libinterp");
      liboctavetestdir = fullfile (testsdir, "liboctave");
      this.add_directory (liboctavetestdir, "Octave builtins: liboctave");
      fixedtestdir = fullfile (testsdir, "fixed");
      this.add_directory (fixedtestdir, "Octave builtins: fixed");
    endfunction

    function add_octave_standard_library (this)
      % Add the tests for the M-code-implemented parts of the Octave "standard library"
      %
      % This is distinct from the add_octave_builtins() method, which adds
      % just the built-in/compiled functions. Maybe these should be combined
      % and add_octave_standard_library should do both. And actually that's a misnomer:
      % The M-file directory contains functions for Octave's internal use, too,
      % not just the public-facing API and its support. Not sure what the nomenclature
      % should be here.
      m_dir = __octave_config_info__ ("fcnfiledir");
      this.add_directory (m_dir, "Octave Standard Library M-code");
    endfunction

    function add_octave_site_m_files (this)
      m_dir = fullfile (matlabroot, "share", "octave", "site", "m");
      this.add_directory (m_dir, "Octave site dir");
    endfunction

    function out = maybe_shuffle_thing (this, data, name)
      if this.shuffle
        if isnumeric (this.shuffle)
          shuffle_seed = this.shuffle;
        else
          shuffle_seed = now;
        endif
        printf ("Shuffling %s with rand seed %.15f\n", name, shuffle_seed);
        out = testify.internal.Util.shuffle (data, shuffle_seed);
      else
        out = data;
      endif
    endfunction

    function out = run_tests (this)

      # Run tests
      ix_filesets = 1:size (this.files, 1);
      ix_filesets = this.maybe_shuffle_thing (ix_filesets, "filesets");

      out = testify.internal.BistRunResult;
      for i_fileset = 1:numel (ix_filesets)
        [tag, files] = this.files{ix_filesets(i_fileset),:};
        files = this.maybe_shuffle_thing (files, "files");
        rslts = testify.internal.BistRunResult;
        abort = false;
        for i_file = 1:numel (files)
          file = files{i_file};
          if this.file_has_tests (file)
            print_test_file_name (file);
            runner = testify.internal.BistRunner (file);
            runner.log_fids = this.log_fid;
            runner.fail_fast = this.fail_fast;
            runner.save_workspace_on_failure = this.save_workspace_on_failure;
            rslt = runner.run_tests;
            print_pass_fail (rslt);
            rslts = rslts + rslt;
            if this.fail_fast && rslt.n_fail > 0
              abort = true;
              break
            endif
          elseif this.file_has_functions (file)
            rslts.files_processed{end+1} = file;
          endif
        endfor
        # Display intermediate summary
        out = out + rslts;
        if abort
          break
        endif
      endfor
      if (! isempty (out.files_with_no_tests))
        if (! isempty (this.log_fid))
          fprintf (this.log_fid, "\nThe following %d files have no tests:\n\n", ...
            numel (out.files_with_no_tests));
          fprintf (this.log_fid, "%s\n", list_in_columns (out.files_with_no_tests, [], "  "));
        endif
      endif

    endfunction

    function out = file_has_tests (this, f)
      str = fileread (f);
      out = ! isempty (regexp (str,
                                  '^%!(assert|error|fail|test|xtest|warning)',
                                  'lineanchors', 'once'));
    endfunction

    function out = file_has_functions (this, f)
      n = length (f);
      if endswith_any (lower (f), ".cc")
        str = fileread (f);
        out = ! isempty (regexp (str,'^(?:DEFUN|DEFUN_DLD|DEFUNX)\>',
                                        'lineanchors', 'once'));
      elseif endswith_any (lower (f), ".m")
        out = true;
      else
        out = false;
      endif
    endfunction

    function out = parse_namespaced_thing (this, thing)
      % Parse a possibly namespace-qualified identifier.
      % Note that this only works for classes and functions, not methods, because
      % it operates on just the name, so it can't differentiate a namespace from
      % a namespaced class that is prefixing a method name
      ix = find (thing == ".");
      if isempty (ix)
        out.namespace = "";
        out.thing = thing;
        out.is_namespaced = false;
      else
        out.namespace = thing(1:ix(end)-1);
        out.thing = thing(ix(end)+1:end);
        out.is_namespaced = true;
      endif
    endfunction

  endmethods

  methods (Access = private)
    function add_fileset (this, tag, files)
      files = cellstr (files);
      files = files(:)';
      this.files = [this.files; {tag files}];
    endfunction
  endmethods
endclassdef

function out = endswith_any (str, endings)
  endings = cellstr (endings);
  for i = 1:numel (endings)
    pat = endings{i};
    if numel (str) >= numel (pat)
      if isequal (str(end-numel (pat) + 1:end), pat)
        out = true;
        return
      endif
    endif
  endfor
  out = false;
endfunction

function print_pass_fail (rslts)
  r = rslts;
  if (r.n_test > 0)
    printf (" PASS   %4d/%-4d", r.n_pass, r.n_test);
    if (r.n_really_fail > 0)
      printf ("\n%68s   %4d", "FAIL", r.n_really_fail);
    endif
    if (r.n_regression > 0)
      printf ("\n%68s   %4d", "REGRESSION", r.n_regression);
    endif
    if (r.n_xfail_bug > 0)
      printf ("\n%68s   %4d", "(reported bug) XFAIL", r.n_xfail_bug);
    endif
    if (r.n_xfail > 0)
      printf ("\n%68s   %4d", "(expected failure) XFAIL", r.n_xfail);
    endif
    if (r.n_skip_feature > 0)
      printf ("\n%68s   %4d", "(missing feature) SKIP", r.n_skip_feature);
    endif
    if (r.n_skip_runtime > 0)
      printf ("\n%68s   %4d", "(run-time condition) SKIP", r.n_skip_runtime);
    endif
  endif
  puts ("\n");
  fflush (stdout);
endfunction

function print_test_file_name (nm)
  nm = strrep (nm, fullfile (matlabroot, "share", "octave", version, ...
    "etc", "tests"), "<Octave/tests>");
  nm = strrep (nm, fullfile (matlabroot, "share", "octave", version, "m"), ...
    "<Octave/m>");
  nm = strrep (nm, fullfile (matlabroot, "share", "octave", version), ...
    "<Octave/share>");
  nm = strrep (nm, matlabroot, "<Octave>");
  filler = repmat (".", 1, 60-length (nm));
  printf ("  %s %s", nm, filler);
endfunction

function out = is_classdef_file (file)
  out = false;
  if ! exist (file, "file")
    return
  endif
  code = fileread (file);
  out = regexp (code, '^\s*classdef\s+', 'lineanchors');
endfunction

