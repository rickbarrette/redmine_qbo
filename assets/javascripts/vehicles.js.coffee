# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

$ ->
  $(document).on 'change', '#customer_id', (evt) ->
    $.ajax 'update_vehicles',
      type: 'GET'
      dataType: 'script'
      data: {
        customer_id: $("#customer_id option:selected").val()
      }
      error: (jqXHR, textStatus, errorThrown) ->
        console.log("AJAX Error: #{textStatus}")
      success: (data, textStatus, jqXHR) ->
console.log("Dynamic vehicle select OK!")
