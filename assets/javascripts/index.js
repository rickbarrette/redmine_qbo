document.addEventListener("DOMContentLoaded", () => {
  if (typeof Stimulus === "undefined") {
    console.error("Stimulus is not loaded. Make sure the UMD script is included first.");
    return;
  }

  const application = Stimulus.Application.start();
  application.register("nested-form", window.NestedFormController);
});