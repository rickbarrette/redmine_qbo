$(function() {
    $("select#issue_customer_id").on("change", function() {
        $.ajax({
            url:  "/filter_vehicles_by_customer",
            type: "GET",
            data: { selected_customer: $("select#issue_customer_id").val() }
        });
    });
});
