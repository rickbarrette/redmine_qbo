function updateLink() {
  console.log("updateLink called");
  const linkElement = document.getElementById("appointment_link");
  const regex = /((?:<br\/>|%3Cbr\/?%3E))([\s\S]*?)(&dates)/gi;
  linkElement.href = linkElement.href.replace(regex, `$1${getSelectedDocs()}$3`);
}

function getSelectedDocs() {
  const appointent_extras = document.querySelectorAll('.appointment');

  let output = '';
  for (const item of appointent_extras) {
    if (item.checked) {
      console.log(`Checked item: ${item.dataset.text} with URL: ${item.dataset.url}`);
      output += `%0A`+ encodeURIComponent(`<a href="${window.location.origin}${item.dataset.url}">${item.dataset.text}</a>`) +`%0A`;
    }
  }
  
  return output;
}
