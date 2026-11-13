# Distribution: GitHub releases for WoWUp, CurseForge and Wago

Players install Mnemosyne with WoWUp or the CurseForge app. The main WoWUp build cannot install from CurseForge (only its Overwolf edition can), so each release goes to two places, both from the Release workflow's one build by the BigWigsMods packager: a GitHub release, with the zip and a `release.json` that tells WoWUp which zip fits the Forever flavor, and the CurseForge project (game type `wow-forever`, 88568). WoWUp installs from a GitHub repository only when it is public, so the repository goes public at the first release; the code stays all rights reserved (`LICENSE`): readable, installable unmodified, not reusable.

The packager writes `release.json` only when it uploads to GitHub itself, which needs the tag to exist first. We build the zip, upload it to CurseForge and attach both files to the draft before publishing, so a failed build never leaves a published release without its download; the workflow writes `release.json` itself, with the packager's fields. Only `main` may publish a release.

Each release also goes to Wago, the catalog WoWUp searches, so WoWUp users can find Mnemosyne by name instead of pasting the GitHub URL. Listing on the WoWUp hub is asked for by hand after the first public release.

The CurseForge and Wago uploads run only while their repository variables are set (`CF_PROJECT_ID`, `WAGO_PROJECT_ID`, with the secrets `CF_API_TOKEN`, `WAGO_API_TOKEN`), so releases work before the projects exist. The .toc carries no project ID.
