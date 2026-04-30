# Sites cleanup

## Overview

in `linux-box-cloudflare` we have both `site` and `sites`.
- `site` is the old folder that was used to host the original static site. It has been deprecated and should be migrated to `sites/landing`.
- `sites` is the new folder that will host all static sites.

in the various setup guides for the linux box, the original `site/index.html` is setup as the landing page in the box, which is ok.
this is done via nginx config.
check which scripts are doing this setup, and update them to point to `sites/landing/index.html` instead of `site/index.html`.
if the scripts are missing, create them in the `scripts` folder.

also create a `scripts/README.md` with instructions on how to run the scripts, and what they do.

if some common js or css files are used by both the landing page and the portfolio page, consider moving them to a shared folder like `sites/common` and updating the paths in the html files accordingly.

## Plan

...
