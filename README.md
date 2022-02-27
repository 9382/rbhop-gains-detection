# rbhop-gains-detection
A script used to examine bot replays in rbhop

You need some sort of injector for this to work. Literally just run one of the scripts and itll start scanning automatically.
itll also print some of the stats in F9 and save it to a log file with the GUI one (if you set it to)

The Live version is designed to work while spectating players, while the GUI one is designed for bots. Do note that the live version is a little more shaky than the bot version - thats just due to the nature of the fact im trynna sort live data, so just deal with what works. And running both at the same time is perfectly stable, so dont worry about that.

## Notes
Just because its not 100%, doesnt mean its cheating. Its more common to see anything from 100 to 90%. It could even get as low as 60s or 50s if you use this in surf.

However, its still possible to tell if its cheated. If the script is *very confident* about the estimated gains and the Accuracy% is decently low, it could be cheated.

If you really cant tell if its cheated or a false alert, ask me (oef#4032) and ill check it myself

(RUNS BEFORE ~ JANUARY 2020 USED DIFFERENT CAMERA LERP LOGIC - THAT MEANS THE SCAN WONT WORK ON THEM.
You can recognise this by how the accuracy and gains prediction accuracy will be wildly low, and the gains will be all over the place)

## The FPS part
The FPS stats part of the GUI one<sub>(ill add it to live later)</sub> is mostly for determining if a run is Timescaled. Of course, theres no easy way to tell with timescale in most cases, so this can only act as a "guide" and not hard proof.

The alert threshold is set to 600 as most people wouldnt hit this high of an fps (timescaling essentially increases the fps of a replay bot), but just because it sets of warnings doesnt mean its timescaled - some people just have stupid good PCs (Although once your at 1000+ id be worried)

A run below 600 fps can also still be timescaled, but thats not really determinable with this.

(Keep in mind: Roblox sucks. ive seen people running at capped 60 FPS get marked at 140 - its stupid)
