on run argv
  set a to item 1 of argv
  set theFile to (a as POSIX file) as alias

  tell application "Music"
    set aTrack to (add theFile)
    set bookmarkable of aTrack to true
  end tell
end run