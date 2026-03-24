# Site Overview Plan: Honeycomb-Style Bubble Portfolio

Here are the files and documentation you need to create the honeycomb-style bubble portfolio, stored in the specific subfolder, and automatically deployed via a GitHub Action.

### Part 1: Repository Structure

Your repository should look like this after you are done:

```text
your-repo-name/
├── .github/
│   └── workflows/
│       └── deploy-site-overview.yml    <-- The GitHub Action
├── sites/
│   └── overview/             <-- Your specific site folder
│       ├── index.html        <-- Main webpage
│       ├── style.css         <-- Core styling & animations
│       └── script.js         <-- Optional JS for graph behavior
├── site/                     <-- Other site folder, will be moved later, leave it as is for now
├── some_other_folder/        <-- Unrelated content
└── README.md
```

---

### Part 2: The Site Files (`sites/overview`)

Create the folder `sites/overview` and add these three files.

#### 1. `sites/overview/index.html`

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Portfolio Overview</title>
    <link rel="stylesheet" href="style.css" />
  </head>
  <body>
    <header>
      <h1>Welcome to My Portfolio</h1>
      <p>Hover over the bubbles below to explore.</p>
    </header>

    <div class="honeycomb-container">
      <div class="bubble project1">
        <div class="bubble-content">
          <img
            src="https://via.placeholder.com/150/ff7f50/ffffff?text=Project+A"
            alt="Project A Thumbnail"
          />
          <div class="text-block">
            <h3>Project Alpha</h3>
            <p>Built a scalable data pipeline using Python.</p>
          </div>
        </div>
      </div>

      <div class="bubble project2">
        <div class="bubble-content">
          <img
            src="https://via.placeholder.com/150/6495ed/ffffff?text=Skills"
            alt="Skills Icon"
          />
          <div class="text-block">
            <h3>Technical Skills</h3>
            <p>React, Node.js, AWS, and modern CSS.</p>
          </div>
        </div>
      </div>

      <div class="bubble project3">
        <div class="bubble-content">
          <img
            src="https://via.placeholder.com/150/3cb371/ffffff?text=Hire+Me"
            alt="Hire Me Icon"
          />
          <div class="text-block">
            <h3>Contact Me</h3>
            <p>Available for freelance opportunities.</p>
          </div>
        </div>
      </div>

      <div class="bubble project4">
        <div class="bubble-content">
          <img
            src="https://via.placeholder.com/150/daa520/ffffff?text=Project+B"
            alt="Project B Thumbnail"
          />
          <div class="text-block">
            <h3>Project Beta</h3>
            <p>Implemented AI image recognition.</p>
          </div>
        </div>
      </div>
    </div>

    <script src="script.js"></script>
  </body>
</html>
```

#### 2. `sites/overview/style.css`

This CSS handles the bubble layout and the animation logic (hovering, scaling, and revealing content).

```css
/* Core Page Styles */
body {
  font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
  background-color: #f0f2f5;
  margin: 0;
  color: #333;
  display: flex;
  flex-direction: column;
  align-items: center;
  padding-top: 50px;
}

header {
  text-align: center;
  margin-bottom: 50px;
}

/* Honeycomb/Bubble Container */
.honeycomb-container {
  position: relative;
  width: 600px;
  height: 400px; /* Adjust based on bubble quantity */
  margin: 0 auto;
}

/* Base Bubble Styling */
.bubble {
  width: 150px;
  height: 150px;
  background-color: white;
  border-radius: 50%; /* Pure Circle */
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
  position: absolute;
  cursor: pointer;
  overflow: hidden; /* Important for reveal effect */
  transition:
    transform 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275),
    box-shadow 0.3s ease;
  z-index: 1; /* Default stack order */
}

/* The Content Inside the Bubble (hidden initially) */
.bubble-content {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  opacity: 0; /* Hidden */
  transform: scale(0.8); /* Shrink slightly */
  transition:
    opacity 0.3s ease,
    transform 0.3s ease;
  text-align: center;
  padding: 10px;
  box-sizing: border-box;
}

.bubble-content img {
  width: 70px;
  height: 70px;
  border-radius: 50%;
  margin-bottom: 10px;
}

.text-block h3 {
  margin: 0;
  font-size: 1.1rem;
  color: #333;
}

.text-block p {
  margin: 5px 0 0;
  font-size: 0.8rem;
  color: #666;
  line-height: 1.2;
}

/* --- Hover Effects: The Core Animation --- */
.bubble:hover {
  transform: scale(1.6); /* Large expansion */
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
  z-index: 10; /* Bring it to the top so it doesn't get blocked */
}

.bubble:hover .bubble-content {
  opacity: 1; /* Reveal content */
  transform: scale(1); /* Return content to normal scale */
}

/* --- Positioning: honeycomb layout --- */
/* You manually set these or use JS to randomize them like a graph */
.project1 {
  top: 50px;
  left: 225px;
  background-color: coral; /* Project 1 theme */
}

.project2 {
  top: 150px;
  left: 100px;
  background-color: cornflowerblue; /* Skills theme */
}

.project3 {
  top: 150px;
  left: 350px;
  background-color: mediumseagreen; /* Contact theme */
}

.project4 {
  top: 250px;
  left: 225px;
  background-color: goldenrod; /* Project 2 theme */
}

/* Optional: if you remove images, show the bubble colors by default */
.bubble:not(:hover) {
  /* If you want the bubbles to start as simple colored circles */
  /* border: 5px solid rgba(255,255,255,0.8); */
}
```

#### 3. `sites/overview/script.js`

You mentioned a "graph of bubbles." If you want them to behave like a _network graph_ (floating and bouncing rather than being stuck at `top: 50px` in CSS), you would use a JS library like D3.js.

However, since you requested the core files, I will provide a minimal `script.js` that makes the bubbles "wiggle" slightly to simulate floating. You can delete this file if you prefer them to stay static.

```javascript
// A minimal script to make bubbles wiggle like a "graph"

document.addEventListener("DOMContentLoaded", () => {
  const bubbles = document.querySelectorAll(".bubble");

  bubbles.forEach((bubble) => {
    // Add a random delay so they don't all wiggle together
    bubble.style.animationDelay = `${Math.random() * 2}s`;
    bubble.classList.add("floating");
  });
});

// Add the floating keyframes to CSS programmatically or paste in style.css
const style = document.createElement("style");
style.textContent = `
    @keyframes float {
        0% { transform: translateY(0px) scale(1); }
        50% { transform: translateY(-8px) scale(1.02); }
        100% { transform: translateY(0px) scale(1); }
    }
    .bubble.floating:not(:hover) {
        animation: float 5s ease-in-out infinite;
    }
`;
document.head.appendChild(style);
```

---

### Part 3: The GitHub Action

Create the folder path `.github/workflows/` in the root of your repo. Then create the following file inside it.

#### `.github/workflows/deploy-site.yml`

This action specifically takes the contents of `sites/overview` and publishes only those files to GitHub Pages.

```yaml
name: Deploy Portfolio Site

on:
  push:
    branches: ["main"] # Or your default branch (e.g., master)
  # Allows you to run this workflow manually from the Actions tab
  workflow_dispatch:

# Sets permissions of the GITHUB_TOKEN to allow deployment to GitHub Pages
permissions:
  contents: read
  pages: write
  id-token: write

# Allow only one concurrent deployment
concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  # Single deploy job
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup GitHub Pages
        uses: actions/configure-pages@v4

      # --- CRITICAL STEP ---
      # This step uploads only the specific subfolder you built.
      # Change 'path' if you rename the folder.
      - name: Upload static assets
        uses: actions/upload-pages-artifact@v3
        with:
          path: "./sites/overview" # <-- We deploy *only* this folder

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

---

### Part 4: Deployment Documentation

Create this file as `DEPLOY.md` (or add its contents to your main `README.md`).

#### `DEPLOY.md`

````markdown
# Portfolio Site Deployment Guide

This guide explains how this repository’s portfolio site (located in `sites/overview`) is built, how to set it up, and how to maintain it.

## 1. Structure Overview

This repository uses a structured layout to keep unrelated content separate from the website.

- **`/.github/workflows/deploy-site.yml`**: The automation script. Whenever you push code to `main`, this script isolates the `sites/overview` folder and publishes its contents to the web.
- **`/sites/overview/`**: The root folder for the website.
  - `index.html`: Holds the structure of the bubbles.
  - `style.css`: Handles the bubble scaling animation on hover.
  - `script.js`: Provides a slight "wiggle" animation to simulate floating bubbles.
- **`/README.md` & `/DEPLOY.md`**: Documentation.

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
  python -m http.server 8000
  ```
  Then, open your web browser and go to `http://localhost:8000`.
````
