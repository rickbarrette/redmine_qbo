function updateLink() {
  const linkElement = document.getElementById("appointment_link");
  const regex = /((?:<br\/>|%3Cbr\/?%3E))([\s\S]*?)(&dates)/gi;
  linkElement.href = linkElement.href.replace(regex, `$1${getSelectedDocs()}$3`);
}

function getSelectedDocs() {
  const invoices = document.querySelectorAll('.invoice-checkbox');
  const estimates = document.querySelectorAll('.estimate-checkbox');

  let output = '';

  for (const i of invoices) {
    if (i.checked) {
      console.log(i.value);
      console.log(i.dataset.doc);
      output += `%0A<a href="${window.location.origin}/invoices/${i.dataset.id}">Invoice:%20${i.dataset.doc}</a>%0A`;
    }
  }

  for (const e of estimates) {
    if (e.checked) {
      console.log(e.value);
      console.log(e.dataset.doc);
      output += `%0A<a href="${window.location.origin}/estimates/${e.value}">Estimate:%20${e.dataset.doc}</a>%0A`;
    }
  }
  
  // You can return the array or use it as needed
  return output;
}
