/* arexx.rexx: Audacity's ARexx port (AUDACITY.1). Start Audacity first, with
 * RexxMast running. Prints PASS or FAIL for each check, then QUITs it and
 * checks that the port has gone. rx tests/arexx.rexx
 * Copyright (c) 2026 AmiCradle Team */
OPTIONS RESULTS
PARSE ARG dummy
bad = 0
IF ~SHOW('P', 'AUDACITY.1') THEN DO
    SAY 'FAIL Audacity is not running (no AUDACITY.1)'
    EXIT 20
END
ADDRESS 'AUDACITY.1'

'VERSION'
CALL check 'VERSION', rc = 0 & POS('Audacity ', result) = 1
'HELP'
CALL check 'HELP', rc = 0 & POS('QUIT', result) > 0 & POS('OPEN', result) > 0 & POS('DO', result) > 0 & POS('PLAY', result) > 0 & POS('STOP', result) > 0
'FAULT 205'
CALL check 'FAULT', rc = 0 & result ~= ''
'NOSUCH'
CALL check 'unknown command', rc = 20
'DEACTIVATE'
CALL check 'DEACTIVATE', rc = 0
'ACTIVATE'
CALL check 'ACTIVATE', rc = 0
'DO "Help: Command=Play"'
CALL check 'DO Help', rc = 0 & result ~= ''
'DO "NoSuchCommand:"'
CALL check 'DO unknown scripting command', rc = 10
'STOP'
CALL check 'STOP', rc = 0
'OPEN NoSuchDrawer/none.aup3'
CALL check 'OPEN missing', rc = 10
'QUIT'
CALL check 'QUIT', rc = 0
DO i = 1 TO 30
    IF ~SHOW('P', 'AUDACITY.1') THEN LEAVE
    ADDRESS COMMAND 'Wait 1'
END
CALL check 'port gone after QUIT', ~SHOW('P', 'AUDACITY.1')
IF bad = 0 THEN SAY 'audacity arexx: ALL PASS'
ELSE SAY 'audacity arexx:' bad 'FAILED'
EXIT bad

check: PARSE ARG what, ok
IF ok THEN SAY 'PASS' what
ELSE DO
    SAY 'FAIL' what '(rc' rc')'
    bad = bad + 1
END
RETURN
