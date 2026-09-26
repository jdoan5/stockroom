// Transfer stock: validate in the browser, post with AJAX, show the result
// without reloading the page, and keep the stock panel current.
$(function () {
    var $form = $("#transfer-form");
    if (!$form.length) return;

    var $result = $("#transfer-result");
    var $stock = $("#sku-stock");
    var $sku = $("#Form_Sku");
    var $button = $("#transfer-submit");

    function showAlert(kind, text) {
        // .text(), never .html(): messages can contain values the user sent.
        $result.html($('<div class="alert py-2"></div>').addClass("alert-" + kind).text(text));
    }

    function loadStock() {
        var sku = $sku.val();
        if (!sku) {
            $stock.html('<p class="text-muted small">Choose a product to see its stock in each warehouse.</p>');
            return;
        }
        $stock.load($stock.data("url") + "?sku=" + encodeURIComponent(sku));
    }

    function clearServerErrors() {
        $result.empty();
        $form.find("[data-valmsg-for]").text("")
             .removeClass("field-validation-error").addClass("field-validation-valid");
    }

    // The server answers 400 with { errors: { Quantity: ["..."] } }. Put each
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

    $sku.on("change", loadStock);

    $form.on("submit", function (e) {
        e.preventDefault();
        if (!$form.valid()) return;   // jQuery Validate, driven by the model's data annotations
        clearServerErrors();

        // Disable while the request is in flight: a double-click would otherwise
        // send two transfers.
        $button.prop("disabled", true).text("Transferring…");

        $.ajax({ url: $form.attr("action"), method: "POST", data: $form.serialize() })
            .done(function (res) {
                showAlert("success", res.message);
                $("#Form_Quantity").val("");
                loadStock();
            })
            .fail(function (xhr) {
                if (xhr.status === 400 && xhr.responseJSON && xhr.responseJSON.errors) {
                    showServerErrors(xhr.responseJSON.errors);
                } else {
                    showAlert("danger", "Something went wrong. Please try again.");
                }
            })
            .always(function () {
                $button.prop("disabled", false).text("Transfer");
            });
    });
});
