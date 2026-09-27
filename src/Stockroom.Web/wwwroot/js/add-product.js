// Add product: validate in the browser, post with AJAX, then show the result
// with links to the next steps and clear the form for the next product.
$(function () {
    var $form = $("#add-product-form");
    if (!$form.length) return;

    var $result = $("#add-product-result");
    var $sku = $("#Form_Sku");
    var $button = $("#add-product-submit");

    function showAlert(kind, text) {
        // .text(), never .html(): messages can contain values the user sent.
        $result.html($('<div class="alert py-2"></div>').addClass("alert-" + kind).text(text));
    }

    // The message plus two links. Built with .text() and .attr() for the same
    // reason as showAlert: the SKU came from the user.
    function showAdded(message, sku) {
        var $links = $('<div class="mt-1"></div>')
            .append($('<a class="alert-link"></a>')
                .attr("href", $result.data("adjust-url") + "?sku=" + encodeURIComponent(sku))
                .text("Adjust stock for " + sku))
            .append(" · ")
            .append($('<a class="alert-link"></a>')
                .attr("href", $result.data("stock-url"))
                .text("See it on the Stock page"));
        $result.html($('<div class="alert alert-success py-2"></div>')
            .append($("<div></div>").text(message))
            .append($links));
    }

    function clearServerErrors() {
        $result.empty();
        $form.find("[data-valmsg-for]").text("")
             .removeClass("field-validation-error").addClass("field-validation-valid");
    }

    // The server answers 400 with { errors: { Sku: ["..."] } }. Put each
    // message in the same span jQuery Validate uses, so server-side and
    // client-side errors look identical. An empty field name is form-wide.
    function showServerErrors(errors) {
        $.each(errors, function (field, messages) {
            var $span = field ? $form.find('[data-valmsg-for="Form.' + field + '"]') : $();
            if ($span.length) {
                $span.text(messages.join(" "))
                     .removeClass("field-validation-valid").addClass("field-validation-error");
            } else {
                showAlert("danger", messages.join(" "));
            }
        });
    }

    // Once a field shows an error, re-check it as it's edited. Left to jQuery
    // Validate, the message would go on blur, which is the mousedown of the next
    // click on the button: the form gets a line shorter, the button moves up out
    // from under the pointer, and the click is lost.
    $form.on("input change", "input, select", function () {
        var $span = $form.find('[data-valmsg-for="' + this.name + '"]');
        if ($span.hasClass("field-validation-error")) {
            $span.text("").removeClass("field-validation-error").addClass("field-validation-valid");
            $(this).valid();   // a client-side error comes straight back if it still applies
        }
    });

    $form.on("submit", function (e) {
        e.preventDefault();
        if (!$form.valid()) return;   // jQuery Validate, driven by the model's data annotations
        clearServerErrors();

        // The database stores the SKU trimmed and in capitals; the links use the same.
        var sku = $sku.val().trim().toUpperCase();

        // Disable while the request is in flight: a double-click would otherwise
        // send the same product twice.
        $button.prop("disabled", true).text("Adding…");

        $.ajax({ url: $form.attr("action"), method: "POST", data: $form.serialize() })
            .done(function (res) {
                showAdded(res.message, sku);
                $form[0].reset();   // back to the page's defaults (reorder point 10, quantity 50)
                $sku.trigger("focus");
            })
            .fail(function (xhr) {
                if (xhr.status === 400 && xhr.responseJSON && xhr.responseJSON.errors) {
                    showServerErrors(xhr.responseJSON.errors);
                } else {
                    showAlert("danger", "Something went wrong. Please try again.");
                }
            })
            .always(function () {
                $button.prop("disabled", false).text("Add product");
            });
    });
});
