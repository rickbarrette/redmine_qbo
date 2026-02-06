function updateLink() {

  const selectedIds = getSelectedInvoiceIds();
 

  const extra = `%0A${selectedIds}`; 

  const linkElement = document.getElementById("appointment_link");
  const absoluteUrl = linkElement.href;
  let result = absoluteUrl.replace(/&dates/g, `${extra}&dates`);

  linkElement.href = result;
  linkElement.textContent = "New Appointment Link";
}

function getSelectedInvoiceIds() {
  // Select all checkboxes with the class 'invoice-checkbox'
  const checkboxes = document.querySelectorAll('.invoice-checkbox');
  
  // Use Array.from to convert NodeList to an array and then filter and map
  const selectedIds = Array.from(checkboxes)
      .filter(checkbox => checkbox.checked) // Keep only checked checkboxes
      .map(checkbox => checkbox.value);     // Extract the value (invoice ID)

  // Display the result (for demonstration)
  console.log(JSON.stringify(selectedIds));
  
  // You can return the array or use it as needed
  return selectedIds;
}
