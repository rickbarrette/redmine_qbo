function updateLink() {
  const linkElement = document.getElementById("appointment_link");
  const regex = /((?:<br\/>|%3Cbr\/?%3E))([\s\S]*?)(&dates)/gi;
  linkElement.href = linkElement.href.replace(regex, `$1${getSelectedDocs()}$3`);
  linkElement.textContent = "New Appointment Link";
}

function getSelectedDocs() {
  const invoices = document.querySelectorAll('.invoice-checkbox');
  const estimates = document.querySelectorAll('.estimate-checkbox');
  
  const invoiceIds = Array.from(invoices)
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.value);

  const estimateIds = Array.from(estimates)
      .filter(checkbox => checkbox.checked)
      .map(checkbox => checkbox.value);

  let output = '';

  for (const value of invoiceIds) {
    output += `%0A<a href="${window.location.origin}/invoices/${value}">Invoice:%20${value}</a>%0A`;
  }

  for (const value of estimateIds) {
    output += `%0A<a href="${window.location.origin}/estimates/${value}">Estimate:%20${value}</a>%0A`;
  }
  
  // You can return the array or use it as needed
  return output;
}
