//= require jquery
//= require jquery-ui-1.12.1
//= require jquery-ui-1.12.1/autocomplete
//= require autocomplete-rails

$('#issue_customer_id').bind('railsAutocomplete.select', function(event, data){
  console.log( data.item.id);
});
