/* Play.rexx: Audacity opens a sound and plays it.
   rx Play.rexx Work:Sounds/song.wav   (Audacity running) */
OPTIONS RESULTS
PARSE ARG file
IF ~SHOW('P', 'AUDACITY.1') THEN DO
    SAY 'Audacity is not running.'
    EXIT 5
END
ADDRESS 'AUDACITY.1'
IF file ~= '' THEN 'OPEN' '"'file'"'
ADDRESS COMMAND 'Wait 2'
'PLAY'
