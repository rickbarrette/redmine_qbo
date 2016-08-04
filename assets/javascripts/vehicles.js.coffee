# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

$ ->
  $(document).on 'change', '#issue_customer_id', (evt) ->
    $window.alert("Customer Changed")
    $.ajax 'update_vehicles',
      type: 'GET'
      dataType: 'script'
      data: {
        customer_id: $("#issue_customer_id option:selected").val()
      }
      error: (jqXHR, textStatus, errorThrown) ->
        console.log("AJAX Error: #{textStatus}")
      success: (data, textStatus, jqXHR) ->
console.log("Dynamic vehicle select OK!")
