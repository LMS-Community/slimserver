// dragdrop.js

function initPlaylistDragDrop(listSelector) {
    // Feature detection for HTML5 drag-and-drop
    if (!("draggable" in document.createElement("div"))) {
        console.warn("This browser does not support HTML5 drag-and-drop.");
        return; // stop script if unsupported
    }

    const list = document.querySelector(listSelector);
    if (!list) {
        console.warn(`No element found for selector: ${listSelector}`);
        return;
    }

    let draggedItem = null;
    // Attach drag-and-drop behavior to direct children
    //list.querySelectorAll(":scope > div").forEach(item => {
    list.querySelectorAll(":scope > div").forEach((item, index) => {
        item.setAttribute("draggable", "true");
        item.setAttribute('data-index', index);

        item.addEventListener("dragstart", function(e) {
            draggedItem = this;
            e.dataTransfer.effectAllowed = "move";
            e.dataTransfer.setData("text/plain", ""); // required in Firefox
            this.classList.add("dragging");
        });

        item.addEventListener("dragend", function(e) {
            this.classList.remove("dragging");
            handlePlaylistDragEnd(e);
            clearDropStyles(list);
            draggedItem = null;
            updateOddEven(list);
        });

        item.addEventListener("dragover", function(e) {
            e.preventDefault();
            e.dataTransfer.dropEffect = "move";

            const bounding = this.getBoundingClientRect();
            const offset = e.clientY - bounding.top;

            clearDropStyles(list);

            if (offset > bounding.height / 2) {
                this.classList.add("drop-target-below");
            } else {
                this.classList.add("drop-target-above");
            }
        });

        item.addEventListener("dragleave", function() {
            clearDropStyles(list);
        });

        item.addEventListener("drop", function(e) {
            e.stopPropagation();
            clearDropStyles(list);

            if (draggedItem !== this) {
                const bounding = this.getBoundingClientRect();
                const offset = e.clientY - bounding.top;
                if (offset > bounding.height / 2) {
                    this.insertAdjacentElement("afterend", draggedItem);
                } else {
                    this.insertAdjacentElement("beforebegin", draggedItem);
                }
            }
        });
    });

    // Initial odd/even setup
    updateOddEven(list);
}

function updateOddEven(list) {
    list.querySelectorAll(":scope > div").forEach((el, index) => {
        el.classList.remove("odd", "even");
        el.classList.add(index % 2 === 0 ? "odd" : "even");
    });
}

function clearDropStyles(list) {
    list.querySelectorAll(".drop-target-above, .drop-target-below").forEach(el => {
        el.classList.remove("drop-target-above", "drop-target-below");
    });
}


// Get the player ID from the DOM and decode it
function getPlayerId() {
    const playerIdElement = document.getElementById('playerid');
    if (playerIdElement) {
        // The MAC address is URL encoded in the DOM, so decode it
        return decodeURIComponent(playerIdElement.textContent || playerIdElement.innerText);
    }
    return null;
}


function handlePlaylistDragEnd(event) {
    const draggedElement = event.target;
    const fromIndex = parseInt(draggedElement.getAttribute('data-index'));
    const toIndex = calculateNewIndex(draggedElement); // Your logic to determine new position
    // Don't make unnecessary calls if position didn't change
    if (fromIndex === toIndex) {
        return;
    }
    let player_id = getPlayerId();
    if (player_id !=null){ 
      movePlaylistItemXHR(player_id, fromIndex, toIndex) 
    }
}


function movePlaylistItemXHR(playerID, fromIndex, toIndex) {
    const xhr = new XMLHttpRequest();
    const url = `/status.html?p0=playlist&p1=move&p2=${fromIndex}&p3=${toIndex}&player=${playerID}&ajax=1`;
    console.log("Calling URL : " + url)

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                console.log('Player ' + playerID + ' playlist item moved successfully from ' + fromIndex + ' to ' + toIndex);
            } else {
                console.error('Failed to move playlist item');
            }
        }
    };
    xhr.open('GET', url, true);
    xhr.send();
}


// Helper function to calculate the new index based on drop position
function calculateNewIndex(draggedElement) {
    const playlistContainer = document.getElementById('playList');
    const allItems = Array.from(playlistContainer.querySelectorAll('.odd, .even'));
    var newIndex=allItems.indexOf(draggedElement);
    return newIndex;
}
