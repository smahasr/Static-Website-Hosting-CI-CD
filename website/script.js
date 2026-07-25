const menuToggle = document.querySelector(".menu-toggle");
const mainNav = document.querySelector(".main-nav");
const navGroups = document.querySelectorAll(".nav-group");
const chatLauncher = document.querySelector(".chat-launcher");
const chatPanel = document.querySelector(".chat-panel");
const chatClose = document.querySelector(".chat-close");
const toast = document.querySelector(".toast");
let toastTimer;

function closeMenus(except) {
  navGroups.forEach((group) => {
    if (group !== except) {
      group.classList.remove("open");
      group.querySelector(".nav-trigger").setAttribute("aria-expanded", "false");
    }
  });
}

navGroups.forEach((group) => {
  const trigger = group.querySelector(".nav-trigger");
  trigger.addEventListener("click", (event) => {
    event.stopPropagation();
    const willOpen = !group.classList.contains("open");
    closeMenus(group);
    group.classList.toggle("open", willOpen);
    trigger.setAttribute("aria-expanded", String(willOpen));
  });
});

menuToggle.addEventListener("click", () => {
  const isOpen = mainNav.classList.toggle("open");
  menuToggle.setAttribute("aria-expanded", String(isOpen));
});

document.addEventListener("click", (event) => {
  if (!event.target.closest(".nav-group")) closeMenus();
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    closeMenus();
    mainNav.classList.remove("open");
    menuToggle.setAttribute("aria-expanded", "false");
    setChat(false);
  }
});

function setChat(open) {
  chatPanel.classList.toggle("open", open);
  chatPanel.inert = !open;
  chatPanel.setAttribute("aria-hidden", String(!open));
  chatLauncher.setAttribute("aria-expanded", String(open));
  if (open) chatClose.focus();
}

chatLauncher.addEventListener("click", () => setChat(!chatPanel.classList.contains("open")));
chatClose.addEventListener("click", () => setChat(false));

function showToast(message) {
  window.clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.add("show");
  toastTimer = window.setTimeout(() => toast.classList.remove("show"), 2600);
}

document.querySelectorAll("[data-toast]").forEach((button) => {
  button.addEventListener("click", () => showToast(button.dataset.toast));
});

document.querySelectorAll("[data-action]").forEach((link) => {
  link.addEventListener("click", (event) => {
    event.preventDefault();
    showToast(link.dataset.action === "build"
      ? "The X6 configurator is ready to begin."
      : "More X6 M60i details are coming up.");
  });
});

mainNav.querySelectorAll("a").forEach((link) => {
  link.addEventListener("click", (event) => {
    event.preventDefault();
    showToast(`${link.textContent.trim()} selected`);
    mainNav.classList.remove("open");
    menuToggle.setAttribute("aria-expanded", "false");
    closeMenus();
  });
});
