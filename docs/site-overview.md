# Portfolio Site Deployment Guide

This guide explains how this repository’s portfolio site (located in `sites/overview`) is built, how to set it up, and how to maintain it.

## 0. Live site

The live site is hosted on GitHub Pages and can be accessed at:
[https://Pitrified.github.io/linux-box-cloudflare/](https://Pitrified.github.io/linux-box-cloudflare/)

## 1. Structure Overview

This repository uses a structured layout to keep unrelated content separate from the website.

- **`/.github/workflows/deploy-site.yml`**: The automation script. Whenever you push code to `main`, this script isolates the `sites/overview` folder and publishes its contents to the web.
- **`/sites/overview/`**: The root folder for the website.
  - `index.html`: Holds the structure of the bubbles.
  - `style.css`: Handles the bubble scaling animation on hover.
  - `script.js`: Provides a slight "wiggle" animation to simulate floating bubbles.

## 2. Initial Setup (One-Time)

Because this repository uses a custom folder deployment via GitHub Actions, you must explicitly enable it.

1.  Go to your repository page on GitHub.
2.  Navigate to **Settings** > **Pages** (in the sidebar under "Code and automation").
3.  Under **Build and deployment** > **Source**, change the dropdown from "Deploy from a branch" to **GitHub Actions**.

## 3. How to Deploy Updates

Once the Initial Setup is complete, deploying is automatic.

1.  Make any changes to the HTML, CSS, or JS inside the `sites/overview` folder on your local machine.
2.  Commit your changes: `git commit -am "Updated portfolio content"`
3.  Push your changes: `git push`

The GitHub Action will automatically start. Within 1-2 minutes, your live site will reflect the updates.

## 4. How to Debug

If your site is not working as expected, follow these steps.

### I. Deployment Failures (The site didn't update)

If your `git push` happened but the site didn't change:

1.  Check the **Actions** tab in your GitHub repository.
2.  Look for the "Deploy Portfolio Site" workflow. If you see a **red X**, click it.
3.  Click the "deploy" job to see the detailed logs and find out where the error occurred (e.g., wrong folder path in the `.yml` file).

### II. Visual Errors (Animations are broken or bubbles overlap wrong)

If the deployment succeeded but the site looks broken:

1.  **Check Browser Console:** Right-click your live site, select "Inspect", and go to the **Console** tab. Look for red text (404 errors) indicating that your `style.css` or `script.js` are not loading. This usually means a file path in `index.html` is wrong.
2.  **Verify CSS `z-index`:** If the bubble enlarges but gets blocked by other bubbles, ensure the `.bubble:hover` class has a high `z-index` (e.g., `z-index: 10;`) in `style.css`.
3.  **Inspect Element:** Use the browser's "Inspect" tool on a bubble to see if your CSS styles are being applied correctly during the hover state.

### III. Local development (Testing before you push)

The fastest way to debug visual issues or animation glitches is to test the site on your own computer before pushing your changes to GitHub. Because GitHub Pages serves static files, you don't need a complex backend to see how it looks.

**Method 1: The Quick Way (File Browser)**

1. Navigate to the `sites/overview` folder on your local machine.
2. Double-click the `index.html` file to open it directly in your web browser (the URL will start with `file:///`).

**Method 2: The Recommended Way (Local Server)**
Sometimes, opening files directly via the `file:///` protocol can block certain external assets or scripts due to browser security policies. Running a simple local server provides a perfectly accurate preview of how the site will behave on GitHub Pages.

- **If using VS Code:** Install the popular "Live Server" extension, right-click the `index.html` file, and select **Open with Live Server**.
- **If using Python:** Since you have a `python_scripts/` folder in your repo, you likely have Python installed. Open your terminal, navigate to the `sites/overview` folder, and run:
  ```bash
  cd sites/overview
  python -m http.server 8000
  ```
  Then, open your web browser and go to `http://localhost:8000`.
