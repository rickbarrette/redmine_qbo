document.addEventListener("turbo:load", () => {
  const selectAllBox = document.getElementById("select-all-batches");
  const checkboxes = document.querySelectorAll(".item-checkbox");

  if (selectAllBox) {
    selectAllBox.addEventListener("change", function() {
      checkboxes.forEach((checkbox) => {
        checkbox.checked = this.checked;
      });
    });

    // Optional: Uncheck "Select All" if an individual box is unchecked
    checkboxes.forEach((checkbox) => {
      checkbox.addEventListener("change", () => {
        if (!checkbox.checked) {
          selectAllBox.checked = false;
        } else if (Array.from(checkboxes).every(c => c.checked)) {
          selectAllBox.checked = true;
        }
      });
    });
  }
});