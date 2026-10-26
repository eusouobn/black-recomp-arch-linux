# game/

Place the extracted **Black (USA/EU)** game files here.

**Required:** `default.xbe` must sit directly inside this folder.

You should end up with something like this inside this folder:

    game/
      README.md      (this file, keep it)
      default.xbe    (you add this)
      ...            (rest of the game dump)

The scripts/build-black-xberecomp-linux.sh script detects this folder
automatically and copies everything into ~/BLACK-XBERecomp-Linux/assets
during the build.

These files are NOT versioned in this repository for copyright reasons.
See the .gitignore in the repository root.
