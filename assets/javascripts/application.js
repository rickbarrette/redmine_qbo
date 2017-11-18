$(function() {
  $("input#issue_customer_id").on("change", function() {
    $.ajax({
      url:  "/filter_vehicles_by_customer",
      type: "GET",
      data: { selected_customer: $("input#issue_customer_id").val() }
    });
    
    $.ajax({
      url:  "/filter_estimates_by_customer",
      type: "GET",
      data: { selected_customer: $("input#issue_customer_id").val() }
    });
  });
    
  $("input#project_customer_id").on("change", function() {
    $.ajax({
      url:  "/filter_vehicles_by_customer",
      type: "GET",
      data: { selected_customer: $("input#project_customer_id").val() }
    });
  });
});
