(function() {
  class NestedFormController extends Stimulus.Controller {
    static targets = ["container", "template"]

    add(event) {
      event.preventDefault();
      const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime());
      this.containerTarget.insertAdjacentHTML("beforeend", content);
    }

    remove(event) {
      event.preventDefault();
      event.target.closest(".nested-fields").remove();
    }
  }

  // Expose globally so index.js can access it
  window.NestedFormController = NestedFormController;
})();