document.addEventListener('DOMContentLoaded', () => {
  const select_all_invoice = document.getElementById('select-all-invoices');
  const invoices = document.querySelectorAll('.invoice-checkbox');

  if (select_all_invoice) {
    select_all_invoice.addEventListener('change', (e) => {
      invoices.forEach(item => item.checked = e.target.checked);
    });
  }

  invoices.forEach(item => {
    item.addEventListener('change', () => {
      const allChecked = Array.from(invoices).every(i => i.checked);
      select_all_invoice.checked = allChecked;
    });
  });
});