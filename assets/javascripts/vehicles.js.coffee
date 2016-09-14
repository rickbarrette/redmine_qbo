$ ->
  $(document).on 'change', '#issue_customer_id', (evt) ->
    $.ajax 'update_vehicles',
      type: 'GET'
      dataType: 'script'
      data: {
        customer_id: $("#issue_customer_id option:selected").val()
      }
      error: (jqXHR, textStatus, errorThrown) ->
        console.log("AJAX Error: #{textStatus}")
      success: (data, textStatus, jqXHR) ->
        console.log("Dynamic country select OK!")
