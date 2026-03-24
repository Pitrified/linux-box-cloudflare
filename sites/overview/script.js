// Stagger the floating animation so bubbles don't all move in sync.
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".bubble").forEach((bubble, i) => {
    bubble.classList.add("floating");
    bubble.style.animationDelay = `${i * 0.9}s`;
  });
});
