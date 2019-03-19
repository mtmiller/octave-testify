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
    test_file_extensions = {'.m', '.cc', '.cc-tst'}
  endproperties

  methods
    function add_file_or_directory (this, file, tag)
      if nargin < 3 || isempty (tag); tag = file; end
      if isfolder (file)
        this.add_directory (file, tag);
      else
        this.add_file (file, tag);
      endif
    endfunction

    function add_file (this, file, tag)
      if nargin < 3 || isempty (tag); tag = file; end
      if isfolder (file)
        error ("MultiBistRunner.add_file: file is a directory: %s", file);
      endif
      this.add_fileset (["file " tag], file);
    endfunction

    function add_directory (this, path, tag, recurse = true)
      if nargin < 3 || isempty (tag); tag = path; end
      if ! isfolder (path)
        error ("MultiBistRunner.add_directory: not a directory: %s", path);
      endif

      files = this.search_directory (path, recurse);
      this.add_fileset (["directory " tag], files);
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
      fcn_file = which (name);
      if ! isempty (fcn_file) && endswith_any (fcn_file, '.m')
        this.add_fileset (["function " name], fcn_file);
      endif
    endfunction

    function add_class (this, name)
      % TODO: Find all the files for this class, looking for multiple @class dirs
      % all along the Octave path. Don't forget namespace support.
      error ("MultiBistRunner: add_class is not yet implemented.");
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

    function out = run_tests (this)

      # Run tests
      out = testify.internal.BistRunResult;
      for i_fileset = 1:size (this.files, 1)
        [tag, files] = this.files{i_fileset,:};
        rslts = testify.internal.BistRunResult;
        printf ("Processing files for %s:\n\n", tag);
        for i_file = 1:numel (files)
          file = files{i_file};
          if this.file_has_tests (file)
            print_test_file_name (file);
		        runner = testify.internal.BistRunner (file);
         	 	runner.output_mode = "quiet";
          	rslt = runner.run_tests;
            print_pass_fail (rslt);
          	rslts = rslts + rslt;
          elseif this.file_has_functions (file)
            rslts.files_processed{end+1} = file;
          endif
        endfor
	      # Display intermediate summary
			  if (! isempty (rslts.files_with_no_tests))
			    printf ("\nThe following files in %s have no tests:\n\n", tag);
			    printf ("%s\n", list_in_columns (rslts.files_with_no_tests, [], "  "));
			  endif
      endfor

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
		    retval = ! isempty (regexp (str,'^(?:DEFUN|DEFUN_DLD|DEFUNX)\>',
		                                    'lineanchors', 'once'));
      elseif endswith_any (lower (f), ".m")
		    out = true;
		  else
		    out = false;
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

function print_pass_fail (r)
  if (r.n_test > 0)
    printf (" PASS   %4d/%-4d", r.n_pass, r.n_test);
    if (r.n_really_fail > 0)
      printf ("\n%71s %3d", "FAIL ", r.n_really_fail);
    endif
    if (r.n_regression > 0)
      printf ("\n%71s %3d", "REGRESSION", r.n_regression);
    endif
    if (r.n_xfail_bug > 0)
      printf ("\n%71s %3d", "(reported bug) XFAIL", n.xfail_bug);
    endif
    if (r.n_xfail > 0)
      printf ("\n%71s %3d", "(expected failure) XFAIL", r.n_xfail);
    endif
    if (r.n_skip_feature > 0)
      printf ("\n%71s %3d", "(missing feature) SKIP", r.n_skip_feature);
    endif
    if (r.n_skip_runtime > 0)
      printf ("\n%71s %3d", "(run-time condition) SKIP", r.n_skip_runtime);
    endif
  endif
  puts ("\n");
  fflush (stdout);
endfunction

function print_test_file_name (nm)
  filler = repmat (".", 1, 60-length (nm));
  printf ("  %s %s", nm, filler);
endfunction

