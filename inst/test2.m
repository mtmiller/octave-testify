## Copyright (C) 2005-2019 Paul Kienzle
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

## -*- texinfo -*-
## @deftypefn  {} {} test2 @var{name}
## @deftypefnx {} {} test2 @var{name} quiet|normal|verbose
## @deftypefnx {} {} test2 ("@var{name}", "quiet|normal|verbose", @var{fid})
## @deftypefnx {} {} test2 ("@var{name}", "quiet|normal|verbose", @var{fname})
## @deftypefnx {} {@var{success}, @var{__rslt__} =} test2 (@dots{})
## @deftypefnx {} {[@var{n}, @var{nmax}, @var{nxfail}, @var{nbug}, @var{nskip}, @var{nrtskip}, @var{nregression}] =} test2 (@dots{})
## @deftypefnx {} {[@var{code}, @var{idx}] =} test2 ("@var{name}", "grabdemo")
## @deftypefnx {} {} test2 ([], "explain", @var{fid})
## @deftypefnx {} {} test2 ([], "explain", @var{fname})
##
## Perform built-in self-tests from the first file in the loadpath matching
## @var{name}.
##
## @code{test2} can be called in either command or functional form.  The exact
## operation of test2 is determined by a combination of mode (interactive or
## batch), reporting level (@qcode{"quiet"}, @qcode{"normal"},
## @qcode{"verbose"}), and whether a logfile or summary output variable is
## used.
##
## The default mode when @code{test2} is called from the command line is
## interactive.  In this mode, tests will be run until the first error is
## encountered, or all tests complete successfully.  In batch mode, all tests
## are run regardless of any failures, and the results are collected for
## reporting.  Tests which require user interaction, i.e., demo blocks,
## are never run in batch mode.
##
## Batch mode is enabled by either 1) specifying a logfile using the third
## argument @var{fname} or @var{fid}, or 2) requesting an output argument
## such as @var{success}, @var{n}, etc.
##
## The optional second argument determines the amount of output to generate and
## which types of tests to run.  The default value is @qcode{"normal"}.
## Requesting an output argument will suppress printing the final summary
## message and any intermediate warnings, unless verbose reporting is
## enabled.
##
## @table @asis
## @item @qcode{"quiet"}
## Print a summary message when all tests pass, or print an error with the
## results of the first bad test when a failure occurs.  Don't run tests which
## require user interaction.
##
## @item @qcode{"normal"}
## Display warning messages about skipped tests or failing xtests during test
## execution.
## Print a summary message when all tests pass, or print an error with the
## results of the first bad test when a failure occurs.  Don't run tests which
## require user interaction.
##
## @item @qcode{"verbose"}
## Display tests before execution.  Print all warning messages.  In interactive
## mode, run all tests including those which require user interaction.
## @end table
##
## The optional third input argument specifies a logfile where results of the
## tests should be written.  The logfile may be a character string
## (@var{fname}) or an open file descriptor ID (@var{fid}).  To enable batch
## processing, but still print the results to the screen, use @code{stdout} for
## @var{fid}.
##
## When called with output arguments (and not in @qcode{"grabdemo"} or @qcode{"explain"}
## mode), returns the following outputs:
##   @code{success} - True if all tests passed, false otherwise
##   @code{__rslt__} - An object holding results data. The format of this object
##                     is undocumented and subject to change at any time.
##
## Example
##
## @example
## @group
## test2 sind
## @result{}
## PASSES 5 out of 5 tests
##
## [n, nmax] = test2 ("sind")
## @result{}
## n =  5
## nmax =  5
## @end group
## @end example
##
## Additional Calling Syntaxes
##
## If the second argument is the string @qcode{"grabdemo"}, the contents of
## any built-in demo blocks are extracted but not executed.  The text for all
## code blocks is concatenated and returned as @var{code} with @var{idx} being
## a vector of positions of the ends of each demo block.  For an easier way to
## extract demo blocks from files, @xref{XREFexample,,example}.
##
## If the second argument is @qcode{"explain"} then @var{name} is ignored and
## an explanation of the line markers used in @code{test2} output reports is
## written to the file specified by @var{fname} or @var{fid}.
##
## @seealso{test, assert, fail, demo, example, error}
## @end deftypefn

## Programming Note: All variables for test2() must use the internal prefix "__".
## Shared variables are eval'ed into the current workspace and therefore might
## collide with the names used in the test.m function itself.

function varargout = test2 (__name, __flag = "normal", __fid = [])

  ## Output from test is prefixed by a "key" to quickly understand the issue.
  persistent __signal_fail  = "!!!!! ";
  persistent __signal_empty = "????? ";
  persistent __signal_block = "***** ";
  persistent __signal_file  = ">>>>> ";
  persistent __signal_skip  = "----- ";

  ## Parse inputs
  if (nargin < 1 || nargin > 3)
    print_usage ();
  elseif (! isempty (__name) && ! ischar (__name))
    error ("test2: NAME must be a string");
  elseif (! ischar (__flag))
    error ("test2: second argument must be a string");
  elseif (isempty (__name) && (nargin != 3 || ! strcmp (__flag, "explain")))
    print_usage ();
  endif

  ## Decide if error messages should be collected.
  __logfile = ! isempty (__fid);
  __batch = __logfile || nargout > 0;
  __cleanup = struct;
  if (__logfile)
    if (ischar (__fid))
      __log_fname = __fid;
      [__fid, __msg] = fopen (__log_fname, "wt");
      if (__fid < 0)
        error ("test2: could not open log file %s: %s", __log_fname, __msg);
      endif
      __cleanup.logfile = onCleanup (@() fclose(__fid));
    endif
    if (! strcmp (__flag, "explain"))
      emit (__fid, "%sprocessing %s\n", __signal_file, __name);
    endif
  else
    __fid = stdout;
  endif

  if (strcmp (__flag, "normal"))
    __grabdemo = false;
    __rundemo  = false;
    if (__logfile)
      __verbose = 1;
    elseif (__batch)
      __verbose = -1;
    else
      __verbose = 0;
    endif
  elseif (strcmp (__flag, "quiet"))
    __grabdemo = false;
    __rundemo  = false;
    __verbose  = -1;
  elseif (strcmp (__flag, "verbose"))
    __grabdemo = false;
    __rundemo  = ! __batch;
    __verbose  = 1;
  elseif (strcmp (__flag, "grabdemo"))
    __grabdemo = true;
    __rundemo  = false;
    __verbose  = -1;
    __demo_code = "";
    __demo_idx = [];
  elseif (strcmp (__flag, "explain"))
    emit (__fid, "# %s new test file\n", __signal_file);
    emit (__fid, "# %s no tests in file\n", __signal_empty);
    emit (__fid, "# %s test had an unexpected result\n", __signal_fail);
    emit (__fid, "# %s test was skipped\n", __signal_skip);
    emit (__fid, "# %s code for the test\n\n", __signal_block);
    emit (__fid, "# Search for the unexpected results in the file\n");
    emit (__fid, "# then page back to find the filename which caused it.\n");
    emit (__fid, "# The result may be an unexpected failure (in which\n");
    emit (__fid, "# case an error will be reported) or an unexpected\n");
    emit (__fid, "# success (in which case no error will be reported).\n");
    return;
  else
    error ("test2: unknown flag '%s'", __flag);
  endif

  ## Locate the file to test.
  __file = locate_test_file (__name, ! __grabdemo, __fid);
  if isempty (__file)
    if (__grabdemo)
      varargout = {"", -1};
    elseif (nargout ==1)
      varargout = {false};
    else
      varargout = {0, 0};
    endif
    return
  endif

  ## Grab the test code from the file.
  __body = __extract_test_code (__file);

  if (isempty (__body))
    if (__grabdemo)
      varargout = {"", []};
    else
      emit (__fid, "%s%s has no tests available\n", __signal_empty, __file);
      if (nargout > 0)
        varargout = {0, 0};
      endif
    endif
    return;
  end
  
  ## Add a dummy comment block to the end for ease of indexing.
  if (__body(end) == "\n")
    __body = ["\n" __body "#"];
  else
    __body = ["\n" __body "\n#"];
  endif

  ## Chop it up into blocks for evaluation.
  __lineidx = find (__body == "\n");
  __blockidx = __lineidx(find (! isspace (__body(__lineidx+1))))+1;

  ## Ready to start tests.
  ## If in batch mode, with a logfile, report what is happening.
  if (__verbose > 0)
    disp ([__signal_file, __file]);
  endif

  ## Track file descriptor leaks
  __fid_list_orig = fopen ("all");

  ## Track variable leaks
  __base_variables_orig = evalin ("base", "who");
  ## Add automatic variable "ans" which may not have been created yet.
  __base_variables_orig{end+1} = "ans";

  ## Track variable leaks
  __global_variables_orig = who ("global");

  ## Assume all tests will pass.
  __all_success = true;

  ## Process each block separately, initially with no shared variables.
  __tests = __successes = 0;
  __xfail = __xbug = __xskip = __xrtskip = __xregression = 0;
  __shared = " ";
  __shared_r = " ";
  __clearfcn = "";
  for __i = 1:numel (__blockidx) - 1

    ## FIXME: Should other global settings be similarly saved and restored?
    orig_wstate = warning ();
    unwind_protect

      ## Extract the block.
      __block = __body(__blockidx(__i):__blockidx(__i+1)-2);

      ## Print the code block before execution if in verbose mode.
      if (__verbose > 0)
        emit (__fid, "%s%s\n", __signal_block, __block);
      endif

      ## Split __block into __type and __code.
      __idx = find (! isletter (__block));
      if (isempty (__idx))
        __type = __block;
        __code = "";
      else
        __type = __block(1:__idx(1)-1);
        __code = __block(__idx(1):length (__block));
      endif

      ## Assume the block will succeed.
      __success = true;
      __msg = [];
      __istest = false;
      __isxtest = false;
      __bug_id = "";
      __fixed_bug = false;

### DEMO

      ## If in __grabdemo mode, then don't process any other block type.
      ## So that the other block types don't have to worry about
      ## this __grabdemo mode, the demo block processor grabs all block
      ## types and skips those which aren't demo blocks.

      __isdemo = strcmp (__type, "demo");
      if (__grabdemo || __isdemo)
        if (__grabdemo && __isdemo)
          if (isempty (__demo_code))
            __demo_code = __code;
            __demo_idx = [1, length(__demo_code)+1];
          else
            __demo_code = [__demo_code, __code];
            __demo_idx = [__demo_idx, length(__demo_code)+1];
          endif

        elseif (__rundemo && __isdemo)
          try
            ## process the code in an environment without variables
            eval (sprintf ("function __test__ ()\n%s\nendfunction", __code));
            __test__;
            input ("Press <enter> to continue: ", "s");
          catch
            __success = false;
            __msg = [__signal_fail "demo failed\n" lasterr()];
          end_try_catch
          clear __test__;

        endif
        ## Code already processed.
        __code = "";

### SHARED

      elseif (strcmp (__type, "shared"))
        ## Separate initialization code from variables.
        __idx = find (__code == "\n");
        if (isempty (__idx))
          __vars = __code;
          __code = "";
        else
          __vars = __code (1:__idx(1)-1);
          __code = __code (__idx(1):length (__code));
        endif

        ## Strip comments off the variables.
        __idx = find (__vars == "%" | __vars == "#");
        if (! isempty (__idx))
          __vars = __vars(1:__idx(1)-1);
        endif

        ## Assign default values to variables.
        try
          __vars = deblank (__vars);
          if (! isempty (__vars))
            eval ([strrep(__vars, ",", "=[];"), "=[];"]);
            __shared = __vars;
            __shared_r = ["[ " __vars "] = "];
          else
            __shared = " ";
            __shared_r = " ";
          endif
        catch
          ## Couldn't declare, so don't initialize.
          __code = "";
          __success = false;
          __msg = [__signal_fail "shared variable initialization failed\n"];
        end_try_catch

        ## Initialization code will be evaluated below.

### FUNCTION

      elseif (strcmp (__type, "function"))
        persistent __fn = 0;
        __name_position = function_name (__block);
        if (isempty (__name_position))
          __success = false;
          __msg = [__signal_fail "test failed: missing function name\n"];
        else
          __name = __block(__name_position(1):__name_position(2));
          __code = __block;
          try
            eval (__code);  # Define the function
            __clearfcn = sprintf ("%sclear %s;\n", __clearfcn, __name);
          catch
            __success = false;
            __msg = [__signal_fail "test failed: syntax error\n" lasterr()];
          end_try_catch
        endif
        __code = "";

### ENDFUNCTION

      elseif (strcmp (__type, "endfunction"))
        ## endfunction simply declares the end of a previous function block.
        ## There is no processing to be done here, just skip to next block.
        __code = "";

### ASSERT
### ASSERT <BUG-ID>
### FAIL
### FAIL <BUG-ID>
###
###   BUG-ID is a bug number from the bug tracker.  A prefix of '*'
###   indicates a bug that has been fixed.  Tests that fail for fixed
###   bugs are reported as regressions.

      elseif (strcmp (__type, "assert") || strcmp (__type, "fail"))
        [__bug_id, __code, __fixed_bug] = getbugid (__code);
        if (isempty (__bug_id))
          __istest = true;
        else
          __isxtest = true;
        endif
        ## Put the keyword back on the code.
        __code = [__type __code];
        ## The code will be evaluated below as a test block.

### ERROR/WARNING

      elseif (strcmp (__type, "error") || strcmp (__type, "warning"))
        __istest = true;
        __iswarning = strcmp (__type, "warning");
        [__pattern, __id, __code] = getpattern (__code);
        if (__id)
          __patstr = ["id=" __id];
        else
          if (! strcmp (__pattern, '.'))
            __patstr = ["<" __pattern ">"];
          else
            __patstr = ifelse (__iswarning, "a warning", "an error");
          endif
        endif
        try
          eval (sprintf ("function __test__(%s)\n%s\nendfunction",
                         __shared, __code));
        catch
          __success = false;
          __msg = [__signal_fail "test failed: syntax error\n" lasterr()];
        end_try_catch

        if (__success)
          __success = false;
          __warnstate = warning ("query", "quiet");
          warning ("on", "quiet");
          ## Clear error and warning strings before starting
          lasterr ("");
          lastwarn ("");
          try
            eval (sprintf ("__test__(%s);", __shared));
            if (! __iswarning)
              __msg = [__signal_fail "error failed.\n" ...
                                     "Expected " __patstr ", but got no error\n"];
            else
              if (! isempty (__id))
                [~, __err] = lastwarn ();
                __mismatch = ! strcmp (__err, __id);
              else
                __err = trimerr (lastwarn (), "warning");
                __mismatch = isempty (regexp (__err, __pattern, "once"));
              endif
              warning (__warnstate.state, "quiet");
              if (isempty (__err))
                __msg = [__signal_fail "warning failed.\n" ...
                                       "Expected " __patstr ", but got no warning\n"];
              elseif (__mismatch)
                __msg = [__signal_fail "warning failed.\n" ...
                                       "Expected " __patstr ", but got <" __err ">\n"];
              else
                __success = true;
              endif
            endif

          catch
            if (! isempty (__id))
              [~, __err] = lasterr ();
              __mismatch = ! strcmp (__err, __id);
            else
              __err = trimerr (lasterr (), "error");
              __mismatch = isempty (regexp (__err, __pattern, "once"));
            endif
            warning (__warnstate.state, "quiet");
            if (__iswarning)
              __msg = [__signal_fail "warning failed.\n" ...
                                     "Expected warning " __patstr ...
                                     ", but got error <" __err ">\n"];
            elseif (__mismatch)
              __msg = [__signal_fail "error failed.\n" ...
                                     "Expected " __patstr ", but got <" __err ">\n"];
            else
              __success = true;
            endif
          end_try_catch
          clear __test__;
        endif
        ## Code already processed.
        __code = "";

### TESTIF HAVE_FEATURE
### TESTIF HAVE_FEATURE ; RUNTIME_CONDITION
### TESTIF HAVE_FEATURE <BUG-ID>
### TESTIF HAVE_FEATURE ; RUNTIME_CONDITION <BUG-ID>
###
###   HAVE_FEATURE is a comma- or whitespace separated list of
###   macro names that may be checked with __have_feature__.
###
###   RUNTIME_CONDITION is an expression to evaluate to check
###   whether some condition is met when the test is executed.  For
###   example, have_window_system.
###
###   BUG-ID is a bug number from the bug tracker.  A prefix of '*'
###   indicates a bug that has been fixed.  Tests that fail for fixed
###   bugs are reported as regressions.

      elseif (strcmp (__type, "testif"))
        __e = regexp (__code, '.$', 'lineanchors', 'once');
        ## Strip any comment and bug-id from testif line before
        ## looking for features
        __feat_line = strtok (__code(1:__e), '#%');
        __idx1 = index (__feat_line, "<");
        if (__idx1)
          __tmp = __feat_line(__idx1+1:end);
          __idx2 = index (__tmp, ">");
          if (__idx2)
            __bug_id = __tmp(1:__idx2-1);
            if (strncmp (__bug_id, "*", 1))
              __bug_id = __bug_id(2:end);
              __fixed_bug = true;
            endif
            __feat_line = __feat_line(1:__idx1-1);
          endif
        endif
        __idx = index (__feat_line, ";");
        if (__idx)
          __runtime_feat_test = __feat_line(__idx+1:end);
          __feat_line = __feat_line(1:__idx-1);
        else
          __runtime_feat_test = "";
        endif
        __feat = regexp (__feat_line, '\w+', 'match');
        __feat = strrep (__feat, "HAVE_", "");
        __have_feat = __have_feature__ (__feat);
        if (__have_feat)
          if (isempty (__runtime_feat_test) || eval (__runtime_feat_test))
            if (isempty (__bug_id))
              __istest = true;
            else
              __isxtest = true;
            endif
            __code = __code(__e + 1 : end);
          else
            __xrtskip += 1;
            __code = ""; # Skip the code.
            __msg = [__signal_skip "skipped test (runtime test)\n"];
          endif
        else
          __xskip += 1;
          __code = ""; # Skip the code.
          __msg = [__signal_skip "skipped test (missing feature)\n"];
        endif

### TEST
### TEST <BUG-ID>
###
###   BUG-ID is a bug number from the bug tracker.  A prefix of '*'
###   indicates a bug that has been fixed.  Tests that fail for fixed
###   bugs are reported as regressions.

      elseif (strcmp (__type, "test"))
        [__bug_id, __code, __fixed_bug] = getbugid (__code);
        if (! isempty (__bug_id))
          __isxtest = true;
        else
          __istest = true;
        endif
        ## Code will be evaluated below.

### XTEST
### XTEST <BUG-ID>
###
###   BUG-ID is a bug number from the bug tracker.  A prefix of '*'
###   indicates a bug that has been fixed.  Tests that fail for fixed
###   bugs are reported as regressions.

      elseif (strcmp (__type, "xtest"))
        __isxtest = true;
        [__bug_id, __code, __fixed_bug] = getbugid (__code);
        ## Code will be evaluated below.

### Comment block.

      elseif (strcmp (__block(1:1), "#"))
        __code = ""; # skip the code

### Unknown block.

      else
        __istest = true;
        __success = false;
        __msg = [__signal_fail "unknown test type!\n"];
        __code = ""; # skip the code
      endif

      ## evaluate code for test, shared, and assert.
      if (! isempty(__code))
        try
          eval (sprintf ("function %s__test__(%s)\n%s\nendfunction",
                         __shared_r, __shared, __code));
          eval (sprintf ("%s__test__(%s);", __shared_r, __shared));
        catch
          if (isempty (lasterr ()))
            error ("test: empty error text, probably Ctrl-C --- aborting");
          else
            __success = false;
            if (__isxtest)
              if (isempty (__bug_id))
                if (__fixed_bug)
                  __xregression += 1;
                  __msg = "regression";
                else
                  __xfail += 1;
                  __msg = "known failure";
                endif
              else
                if (__fixed_bug)
                  __xregression += 1;
                else
                  __xbug += 1;
                endif
                if (all (isdigit (__bug_id)))
                  __bug_id = ["https://octave.org/testfailure/?" __bug_id];
                endif
                if (__fixed_bug)
                  __msg = ["regression: " __bug_id];
                else
                  __msg = ["known bug: " __bug_id];
                endif
              endif
            else
              __msg = "test failed";
            endif
            __msg = [__signal_fail __msg "\n" lasterr()];
          endif
        end_try_catch
        clear __test__;
      endif

      ## All done.  Remember if we were successful and print any messages.
      if (! isempty (__msg) && (__verbose >= 0 || __logfile))
        ## Make sure the user knows what caused the error.
        if (__verbose < 1)
          emit (__fid, "%s%s\n", __signal_block, __block);
        endif
        emit (__fid, "%s\n", __msg);
        ## Show the variable context.
        if ((! ismember(__type, {"error", "testif", "xtest"})) && ! all (__shared == " "))
          emit (__fid, "shared variables ");
          eval (sprintf ("fdisp(__fid,vars2struct(%s));", __shared));
        endif
      endif
      if (! __success && ! __isxtest)
        __all_success = false;
        ## Stop after 1 error if not in batch mode or only pass/fail requested.
        if (! __batch || nargout == 1)
          if (nargout > 0)
            varargout = {0, 0};
          endif
          return;
        endif
      endif
      __tests += (__istest || __isxtest);
      __successes += __success && (__istest || __isxtest);

    unwind_protect_cleanup
      warning ("off", "all");
      warning (orig_wstate);
    end_unwind_protect
  endfor

  ## Clear any functions created during test run.
  eval (__clearfcn, "");

  ## Verify test file did not leak file descriptors.
  if (! isempty (setdiff (fopen ("all"), __fid_list_orig)))
    warning ("test2: file %s leaked file descriptors\n", __file);
  endif

  ## Verify test file did not leak variables in to base workspace.
  __leaked_vars = setdiff (evalin ("base", "who"), __base_variables_orig);
  if (! isempty (__leaked_vars))
    warning ("test2: file %s leaked variables to base workspace:%s\n",
             __file, sprintf (" %s", __leaked_vars{:}));
  endif

  ## Verify test file did not leak global variables.
  __leaked_vars = setdiff (who ("global"), __global_variables_orig);
  if (! isempty (__leaked_vars))
    warning ("test2: file %s leaked global variables:%s\n",
             __file, sprintf (" %s", __leaked_vars{:}));
  endif

  if (nargout == 0)
    if (__tests || __xfail || __xbug || __xskip || __xrtskip)
      if (__xfail || __xbug)
        if (__xfail && __xbug)
          printf ("PASSES %d out of %d test%s (%d known failure%s; %d known bug%s)\n",
                  __successes, __tests, ifelse (__tests > 1, "s", ""),
                  __xfail, ifelse (__xfail > 1, "s", ""),
                  __xbug, ifelse (__xbug > 1, "s", ""));
        elseif (__xfail)
          printf ("PASSES %d out of %d test%s (%d known failure%s)\n",
                  __successes, __tests, ifelse (__tests > 1, "s", ""),
                  __xfail, ifelse (__xfail > 1, "s", ""));
        elseif (__xbug)
          printf ("PASSES %d out of %d test%s (%d known bug%s)\n",
                  __successes, __tests, ifelse (__tests > 1, "s", ""),
                  __xbug, ifelse (__xbug > 1, "s", ""));
        endif
      else
        printf ("PASSES %d out of %d test%s\n", __successes, __tests,
               ifelse (__tests > 1, "s", ""));
      endif
      if (__xskip)
        printf ("Skipped %d test%s due to missing features\n", __xskip,
                ifelse (__xskip > 1, "s", ""));
      endif
      if (__xrtskip)
        printf ("Skipped %d test%s due to run-time conditions\n", __xrtskip,
                ifelse (__xrtskip > 1, "s", ""));
      endif
    else
      printf ("%s%s has no tests available\n", __signal_empty, __file);
    endif
  elseif (__grabdemo)
    varargout = {__demo_code, __demo_idx};
  elseif (nargout > 0)
    __n = __successes;
    __nmax = __tests;
    __nxfail = __xfail;
    __nbug = __xbug;
    __nskip = __xskip;
    __nrtskip = __xrtskip;
    __nregression = __xregression;
    __rslt = testify.internal.BistRunResult(__n, __nmax, __nxfail, __nbug, ...
      __nskip, __nrtskip, __nregression);
    __rslt.files_with_tests{end+1} = __file;
    if (__rslt.n_really_fail > 2)
      __rslt.failed_files{end+1} = __file;
    endif
    if nargout > 2
      varargout = {__n, __nmax, __nxfail, __nbug, __nskip, __nrtskip, __nregression};
    else
      varargout = {__n, __rslt};
    endif
  endif

endfunction

function emit (fid, format, varargin)
  fprintf (fid, format, varargin{:});
  fflush (fid);
endfunction

## Locate the file to run tests on
function file = locate_test_file (name, verbose, fid)
  # Locates file to run tests on for a name.
  # If not found, emits a diagnostic message about tests-not-found.
  #
  # inputs:
  #   name - file to search for, loosely defined
  #   verbose - whether to print diagnostic messages to fid when file is not found.
  #   fid - file id to write progress messages to
  # outputs:
  #   file - full path to located file, including extension (charvec). Empty
  #     if file was not found.
  
  file = file_in_loadpath (name, "all");
  if (isempty (file))
    file = file_in_loadpath ([name ".m"], "all");
  endif
  if (isempty (file))
    file = file_in_loadpath ([name ".cc"], "all");
  endif
  if (isempty (file))
    testsdir = __octave_config_info__ ("octtestsdir");
    candidates = {
      fullfile(testsdir, name)
      fullfile(testsdir, [name "-tst"])
      fullfile(testsdir, [name ".cc-tst"])
      fullfile(testsdir, [name ".in.yy-tst"])
    };
    for i = 1:numel (candidates)
      if exist (candidates{i}, "file")
        file = candidates{i};
        break
      endif
    endfor
  endif
  if (iscell (file))
    if (isempty (file))
      file = "";
    else
      file = file{1};  # If there are duplicates, return first in path. 
    endif
  endif
  if (isempty (file))
    if (verbose)
      signal_empty = "????? ";
      ftype = exist (name);
      if (ftype == 3)
        fprintf (fid, "%s%s source code with tests for dynamically linked function not found\n", ...
          signal_empty, name);
      elseif (ftype == 5)
        fprintf (fid, "%s%s is a built-in function\n", ...
          signal_empty, name);
      elseif (any (strcmp (__operators__ (), name)))
        fprintf (fid, "%s%s is an operator\n", ...
          signal_empty, name);
      else
        fprintf (fid, "%s%s does not exist in path\n", ...
          signal_empty, name);
      endif
      fflush (fid);
    endif
    file = [];
  endif
endfunction

## Create struct with fieldnames the name of the input variables.
function s = vars2struct (varargin)
  for i = 1:nargin
    s.(inputname (i)) = varargin{i};
  endfor
endfunction

## Find [start,end] of fn in 'function [a,b] = fn'.
function pos = function_name (def)

  pos = [];

  ## Find the end of the name.
  right = find (def == "(", 1);
  if (isempty (right))
    return;
  endif
  right = find (def(1:right-1) != " ", 1, "last");

  ## Find the beginning of the name.
  left = max ([find(def(1:right)==" ", 1, "last"), ...
               find(def(1:right)=="=", 1, "last")]);
  if (isempty (left))
    return;
  endif
  left += 1;

  ## Return the end points of the name.
  pos = [left, right];

endfunction

## Strip <pattern> from '<pattern> code'.
## Optionally also handles 'id=ID code'
function [pattern, id, rest] = getpattern (str)

  pattern = ".";
  id = [];
  rest = str;
  str = trimleft (str);
  if (! isempty (str) && str(1) == "<")
    close = index (str, ">");
    if (close)
      pattern = str(2:close-1);
      rest = str(close+1:end);
    endif
  elseif (strncmp (str, "id=", 3))
    [id, rest] = strtok (str(4:end));
  endif

endfunction

## Strip <bug-id> from '<pattern> code'.
function [bug_id, rest, fixed] = getbugid (str)

  bug_id = "";
  rest = str;
  fixed = false;

  str = trimleft (str);
  if (! isempty (str) && str(1) == "<")
    close = index (str, ">");
    if (close)
      bug_id = str(2:close-1);
      if (strncmp (bug_id, "*", 1))
        bug_id = bug_id(2:end);
        fixed = true;
      endif
      rest = str(close+1:end);
    endif
  endif

endfunction


## Strip '.*prefix:' from '.*prefix: msg\n' and strip trailing blanks.
function msg = trimerr (msg, prefix)
  idx = index (msg, [prefix ":"]);
  if (idx > 0)
    msg(1:idx+length(prefix)) = [];
  endif
  msg = strtrim (msg);
endfunction

## Strip leading blanks from string.
function str = trimleft (str)
  idx = find (! isspace (str), 1);
  str = str(idx:end);
endfunction

## Get test code from a given file
function body = __extract_test_code (file)
  fid = fopen (file, "rt");
  body = "";
  if (fid >= 0)
    while (ischar (ln = fgets (fid)))
      if (strncmp (ln, "%!", 2))
        body = [body, ln(3:end)];
      endif
    endwhile
    fclose (fid);
  endif
endfunction

## Developer's note: Most of these tests don't actually test test2, since
## they're designed to work with Octave's BIST functionality, which will 
## implicitly call test(), not test2().

## example from toeplitz
%!shared msg1,msg2
%! msg1 = "C must be a vector";
%! msg2 = "C and R must be vectors";
%!fail ("toeplitz ([])", msg1)
%!fail ("toeplitz ([1,2;3,4])", msg1)
%!fail ("toeplitz ([1,2],[])", msg2)
%!fail ("toeplitz ([1,2],[1,2;3,4])", msg2)
%!fail ("toeplitz ([1,2;3,4],[1,2])", msg2)
%!test fail ("toeplitz", "Invalid call to toeplitz")
%!fail ("toeplitz (1, 2, 3)", "Invalid call to toeplitz")
%!test assert (toeplitz ([1,2,3], [1,4]), [1,4; 2,1; 3,2])
%!assert (toeplitz ([1,2,3], [1,4]), [1,4; 2,1; 3,2])
%!demo toeplitz ([1,2,3,4],[1,5,6])

## example from kron
%!error <Invalid call to kron> kron ()
%!error <Invalid call to kron> kron (1)
%!test assert (isempty (kron ([], rand (3, 4))))
%!test assert (isempty (kron (rand (3, 4), [])))
%!test assert (isempty (kron ([], [])))
%!shared A, B
%!test
%! A = [1, 2, 3; 4, 5, 6];
%! B = [1, -1; 2, -2];
%!assert (size (kron (zeros (3, 0), A)), [ 3*rows(A), 0 ])
%!assert (size (kron (zeros (0, 3), A)), [ 0, 3*columns(A) ])
%!assert (size (kron (A, zeros (3, 0))), [ 3*rows(A), 0 ])
%!assert (size (kron (A, zeros (0, 3))), [ 0, 3*columns(A) ])
%!assert (kron (pi, e), pi*e)
%!assert (kron (pi, A), pi*A)
%!assert (kron (A, e), e*A)
%!assert (kron ([1, 2, 3], A), [ A, 2*A, 3*A ])
%!assert (kron ([1; 2; 3], A), [ A; 2*A; 3*A ])
%!assert (kron ([1, 2; 3, 4], A), [ A, 2*A; 3*A, 4*A ])
%!test
%! res = [1,-1,2,-2,3,-3; 2,-2,4,-4,6,-6; 4,-4,5,-5,6,-6; 8,-8,10,-10,12,-12];
%! assert (kron (A, B), res);
%!shared  # clear out shared variables

## Now verify test2() itself

## Test 'fail' keyword
%!fail ("test2", "Invalid call to test2")  # no args, generates usage()
%!fail ("test2 (1,2,3,4)", "usage.*test") # too many args, generates usage()
%!fail ('test2 ("test", "invalid")', "unknown flag")  # incorrect args
%!fail ('garbage','garbage.*undefined')  # usage on nonexistent function should be

## Test 'error' keyword
%!error test2              # no args, generates usage()
%!error test2 (1,2,3,4)    # too many args, generates usage()
%!error <unknown flag> test2 ("test", "invalid"); # incorrect args
%!error test2 ("test", "invalid");  # test without pattern
%!error <'garbage' undefined> garbage; # usage on nonexistent function is error

## Test 'warning' keyword
%!warning warning ("warning message");   # no pattern
%!warning <warning message> warning ("warning message");   # with pattern

## Test 'shared' keyword
%!shared a                # create a shared variable
%!test a = 3;             # assign to a shared variable
%!test assert (a, 3)      # variable should equal 3
%!shared b,c              # replace shared variables
%!test assert (! exist ("a", "var"));  # a no longer exists
%!test assert (isempty (b));   # variables start off empty
%!shared a,b,c            # recreate a shared variable
%!test assert (isempty (a));   # value is empty even if it had a previous value
%!test a=1; b=2; c=3;   # give values to all variables
%!test assert ([a,b,c], [1,2,3]); # test all of them together
%!test c=6;               # update a value
%!test assert ([a,b,c], [1,2,6]); # show that the update sticks
%!shared                  # clear all shared variables
%!test assert (! exist ("a", "var")) # show that they are cleared
%!shared a,b,c            # support for initializer shorthand
%! a=1; b=2; c=4;
%!shared                  # clear all shared variables for remainder of tests

## Test 'function' keyword
%!function x = __test_a (y)
%!  x = 2*y;
%!endfunction
%!assert (__test_a (2), 4)  # Test a test function

%!function __test_a (y)
%!  x = 2*y;
%!endfunction
%!test
%! __test_a (2);            # Test a test function with no return value

%!function [x,z] = __test_a (y)
%!  x = 2*y;
%!  z = 3*y;
%!endfunction
%!test
%! [x,z] = __test_a (3);    # Test a test function with multiple returns
%! assert (x,6);
%! assert (z,9);

## Test 'assert' keyword
%!assert (isempty ([]))     # support for test assert shorthand
%!assert (size (ones (1,2,3)), [1 2 3])

## Test 'demo' keyword
%!demo                      # multiline demo block
%! t = [0:0.01:2*pi]; x = sin (t);
%! plot (t,x);
%! % you should now see a sine wave in your figure window

%!demo a=3                  # single line demo blocks work too

%!test
%! [code, idx] = test2 ("test", "grabdemo");
%! assert (numel (idx), 4);
%! assert (code(idx(3):end),
%!         " a=3                  # single line demo blocks work too");

## Test 'testif' keyword
%!testif HAVE_INVALID_FEATURE
%! error ("testif executed code despite not having feature");

## Test 'xtest' keyword
%!xtest
%! assert (1, 1);      # Test passes
%!xtest <53613>
%! assert (0, 1);      # Test fails

## Test comment block.  It can contain anything.
%!##
%! it is the "#" as the block type that makes it a comment
%! and it stays as a comment even through continuation lines
%! which means that it works well with commenting out whole tests

## Test test2() input validation
%!error <NAME must be a string> test2 (1)
%!error <second argument must be a string> test2 ("ls", 1)
%!error test2 ([], "normal")

## All of the following tests should fail.  These tests should
## be disabled unless you are developing test() since users don't
## like to be presented with known failures.
## %!test   error("---------Failure tests.  Use test('test','verbose',1)");
## %!test   assert([a,b,c],[1,3,6]);   # variables have wrong values
## %!invalid                   # unknown block type
## %!error  toeplitz([1,2,3]); # correct usage
## %!test   syntax errors)     # syntax errors fail properly
## %!shared garbage in         # variables must be comma separated
## %!error  syntax++error      # error test fails on syntax errors
## %!error  "succeeds.";       # error test fails if code succeeds
## %!error <wrong pattern> error("message")  # error pattern must match
## %!demo   with syntax error  # syntax errors in demo fail properly
## %!shared a,b,c
## %!demo                      # shared variables not available in demo
## %! assert (exist ("a", "var"))
## %!error
## %! test ('/etc/passwd');
## %! test ("nonexistent file");
## %! ## These don't signal an error, so the test for an error fails.  Note
## %! ## that the call doesn't reference the current fid (it is unavailable),
## %! ## so of course the informational message is not printed in the log.