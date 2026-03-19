(function () {

  // Helper: escape HTML for safety
  function escapeHtml(str) {
    return $("<div>").text(str).html();
  }

  // Helper: highlight all occurrences of term (case-insensitive)
  function highlightTerm(text, term) {
    if (!term) return text;
    const escapedTerm = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const regex = new RegExp("(" + escapedTerm + ")", "ig");
    return text.replace(regex, "<strong>$1</strong>");
  }

  window.initCustomerAutocomplete = function(context) {
    let scope = context || document;

    $(scope).find(".customer-name").each(function() {
      if ($(this).data("autocomplete-initialized")) return;
      $(this).data("autocomplete-initialized", true);

      let $input = $(this);

      let ac = $input.autocomplete({
        appendTo: "body",   // crucial for Redmine positioning
        minLength: 2,

        source: function(request, response) {
          $.getJSON("/customers/autocomplete", { q: request.term })
            .done(function(data) {
              response(data.map(function(item) {
                // combine secondary info
                let secondary = [];
                if (item.phone_number) secondary.push(item.phone_number);
                if (item.mobile_phone_number) secondary.push(item.mobile_phone_number);

                let meta = secondary.length ? " (" + secondary.join(" • ") + ")" : "";

                // escape HTML to avoid XSS
                let safeText = escapeHtml(item.name + meta);

                return {
                  label: item.name + meta,      // plain fallback
                  value: item.name,             // goes into input
                  id: item.id,
                  html: highlightTerm(safeText, request.term)
                };
              }));
            })
            .fail(function() {
              response([]);
            });
        },

        select: function(event, ui) {
          $input.val(ui.item.value);  // visible text
          $("#customer_id").val(ui.item.id); // hidden ID

          // trigger Redmine form update safely
          setTimeout(function() {
            $("#customer_id").trigger("change");
          }, 0);

          return false;
        },

        change: function(event, ui) {
          // clear hidden field if no valid selection
          if (!ui.item && !$input.val()) {
            $("#customer_id").val("");
          }
        }
      });

      // Render item HTML for highlight
      ac.autocomplete("instance")._renderItem = function(ul, item) {
        return $("<li>")
          .append($("<div>").html(item.html))
          .appendTo(ul);
      };
    });
  };

  // Re-init after Redmine AJAX form updates
  $(document).on("ajaxComplete", function() {
    if (window.initCustomerAutocomplete) {
      window.initCustomerAutocomplete(document);
    }
  });

  // Init on page load
  $(document).ready(function() {
    window.initCustomerAutocomplete(document);
  });

  // Also init on Turbo/Redmine load events
  document.addEventListener("turbo:load", function() {
    window.initCustomerAutocomplete(document);
  });

})();