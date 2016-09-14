
function customerSelected() {
  customer_id = $('issue_customer_id').getValue();
  console.log(customer_id);
}

document.observe('dom:loaded', function() {
  customerSelected();
  $('issue_customer_id').observe('change', customerSelected);
});
