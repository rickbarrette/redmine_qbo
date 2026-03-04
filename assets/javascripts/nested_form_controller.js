(function () {
  function initNestedForms() {
    document.querySelectorAll("[data-nested-form]").forEach(function (wrapper) {
      if (wrapper.dataset.initialized === "true") return;
      wrapper.dataset.initialized = "true";

      const container = wrapper.querySelector("[data-nested-form-container]");
      const template = wrapper.querySelector("[data-nested-form-template]");

      if (!container || !template) return;

      wrapper.addEventListener("click", function (event) {
        const addButton = event.target.closest("[data-nested-form-add]");
        const removeButton = event.target.closest("[data-nested-form-remove]");

        // ADD
        if (addButton) {
          event.preventDefault();

          const content = template.innerHTML.replace(
            /NEW_RECORD/g,
            Date.now().toString()
          );

          container.insertAdjacentHTML("beforeend", content);
        }

        // REMOVE
        if (removeButton) {
          event.preventDefault();

          const lineItem = removeButton.closest(wrapper.dataset.wrapperSelector);
          if (!lineItem) return;

          const destroyField = lineItem.querySelector("input[name*='_destroy']");

          if (destroyField) {
            destroyField.value = "1";
            lineItem.style.display = "none";
          } else {
            lineItem.remove();
          }
        }
      });
    });
  }

  // Works for full load
  document.addEventListener("DOMContentLoaded", initNestedForms);

  // Works for Turbo navigation
  document.addEventListener("turbo:load", initNestedForms);
})();