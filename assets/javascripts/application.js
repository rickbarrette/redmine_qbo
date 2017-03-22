$(function() {
  $("input#issue_customer").autocomplete({ 
    source: function (request, response) {
      $.ajax({ url:  "/filter_vehicles_by_customer", type: "GET", data: { selected_customer: $("input#issue_customer").val() } });
    });
  });
});
