$("#issue_vehicles_id").empty().append("<%= escape_javascript(render(:partial => @vehicles)) %>")
