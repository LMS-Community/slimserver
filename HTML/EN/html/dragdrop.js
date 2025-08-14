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
    list.querySelectorAll(":scope > div").forEach((item, index) => {
        item.setAttribute("draggable", "true");
        item.setAttribute('data-index', index);

        item.addEventListener("dragstart", function(e) {
            draggedItem = this;
            e.dataTransfer.effectAllowed = "move";
            e.dataTransfer.setData("text/plain", index); // required in Firefox
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


function handlePlaylistDragEnd(event) {
    const draggedElement = event.target;
    const fromIndex = parseInt(draggedElement.getAttribute('data-index'));
    const toIndex = calculateNewIndex(draggedElement); // Your logic to determine new position
    // Don't make unnecessary calls if position didn't change
    if (fromIndex === toIndex) {
        return;
    }
    //movePlaylistItemXHR(fromIndex, toIndex);
    movePlaylistItemFetch(fromIndex, toIndex) ;
}


function movePlaylistItemFetch(fromIndex, toIndex) {
    const jsonRpcPayload = {
        id: 1,
        method: "slim.request",
        params: [
            playerid, // The MAC address or ID of the current player
            [
                "playlist",
                "move",
                fromIndex,
                toIndex
            ]
        ]
    };
    
    fetch('/jsonrpc.js', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(jsonRpcPayload)
    })
    .then(response => response.json())
    .then(data => {
        console.log('Playlist move successful:', data);
    })
    .catch(error => {
        console.error('Error moving playlist item:', error);
    });
}



function movePlaylistItemXHR(fromIndex, toIndex) {
    if (playerid==null){return;}
    if (isNaN(fromIndex)) {return;}
    if (isNaN(toIndex)) {return;}
    const xhr = new XMLHttpRequest();
    const url = `/status.html?p0=playlist&p1=move&p2=${fromIndex}&p3=${toIndex}&player=${playerid}&ajax=1`;
    console.log("Calling URL : " + url)

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                console.log('Player ' + playerid + ' playlist item moved successfully from ' + fromIndex + ' to ' + toIndex);
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
