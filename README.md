MW2 UTILITY - COMBINED FOV + MUSIC

This combines the two features already proven on your exact Steam
Modern Warfare 2 (2009) Multiplayer x64 executable.

VERIFIED GAME BUILD
-------------------
SHA-256:
3F307EA47940F63936FA41F01ED4A6DEB93493CFD4BF98FBC896A017083B69FA

FEATURES
--------
FOV
- Uses the same cg_fov live-memory approach as the working FoV changer.
- Range: 65 to 90.
- Default: 90.
- Maintains the selected value while enabled.
- Restores the original value on shutdown when it is safe to do so.

MUSIC
- Uses the channels proven during live testing:
    13 = menu
    32 = music
    33 = musicnopause
- Mutes menu and in-game music.
- Leaves other sound channels alone.
- Restores the captured mixer values when disabled or when the utility closes.

AUTO-RECONNECT
--------------
The utility watches for iw4mp.exe.

You can:
1. Launch the utility before MW2.
2. Start MW2 through Steam.
3. The utility connects automatically.
4. If MW2 closes and restarts, it reconnects automatically and reapplies
   the selected FoV/music settings.

NO GROWING LOG
--------------
This version does not create a log file.

HOW TO RUN
----------
Recommended:
    Double-click "Launch MW2 Utility.vbs"

That launches the GUI without a black PowerShell window.

Fallback:
    "Launch MW2 Utility - Console Fallback.bat"

UI
--
- Maintain FoV: turn FoV enforcement on/off.
- FoV box: 65-90.
- Disable all music: menu + in-game.
- Connect / Apply: manually reconnect/apply if needed.
- Restore & Stop: restores settings and stops auto-connect.
- Resume Auto-Connect: starts watching for MW2 again.

NOTES
-----
No original IWD, EXE, or config file is modified.

The utility is intentionally version-specific and refuses a different
iw4mp.exe SHA-256 rather than guessing memory addresses.

As with the working FoV changer and music tests, this uses live
process-memory reads/writes. Test in private/offline use rather than
assuming compatibility with VAC/public matchmaking.

If Windows blocks the VBS launcher, use the console fallback BAT instead.
