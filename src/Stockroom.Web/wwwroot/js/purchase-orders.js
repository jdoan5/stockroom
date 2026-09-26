// Receive a purchase order with one click, then reload just the table.
$(function () {
    var $table = $("#po-table");
    if (!$table.length) return;

    var $result = $("#po-result");
    var token = $('input[name="__RequestVerificationToken"]').val();

    function showAlert(kind, text) {
        $result.html($('<div class="alert py-2"></div>').addClass("alert-" + kind).text(text));
    }

    // Delegated to the container: the table is replaced after each receipt, and
    // handlers bound directly to the old buttons would be lost with it.
    $table.on("click", ".js-receive", function () {
        var $btn = $(this);
        var po = $btn.data("po");
        if (!window.confirm("Receive every outstanding line on " + po + "?")) return;

        $btn.prop("disabled", true).text("Receiving…");

        $.ajax({
            url: $table.data("receive-url"),
            method: "POST",
            data: { poNumber: po },
            headers: { RequestVerificationToken: token }   // anti-forgery, since there's no form
        })
            .done(function (res) {
                showAlert("success", res.message);
                $table.load($table.data("table-url"));
            })
            .fail(function (xhr) {
                showAlert("danger", (xhr.responseJSON && xhr.responseJSON.message) || "Something went wrong. Please try again.");
                $btn.prop("disabled", false).text("Receive");
            });
    });
});
