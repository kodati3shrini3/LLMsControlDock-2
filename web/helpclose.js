// Help page: each open topic has a round collapse button; a click closes that topic and brings its title back into view. The buttons are hidden in the page and shown here, because they do nothing without this script.
(function () {
  // Every collapse button on the page.
  var buttons = document.querySelectorAll('button.helpclose');
  // Go through them.
  buttons.forEach(function (btn) {
    // Show the button: the script is running.
    btn.hidden = false;
    // When the person clicks it.
    btn.addEventListener('click', function () {
      // The topic that holds the button.
      var topic = btn.closest('details');
      // Nothing to close without one.
      if (!topic) {
        // Stop here.
        return;
      }
      // Close the topic.
      topic.open = false;
      // Bring the title back into view, because the bottom button leaves the person far down the page.
      topic.scrollIntoView({ block: 'start' });
    });
  });
})();
