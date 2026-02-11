import Foundation

enum WiFiTransferHTML {
    static let mainPage: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VaultBox Wi-Fi Transfer</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #1C1C1E;
            color: #F2F2F7;
            min-height: 100vh;
            padding: 20px;
        }
        .header {
            text-align: center;
            padding: 30px 0;
        }
        .header h1 {
            font-size: 24px;
            font-weight: 700;
            margin-bottom: 4px;
        }
        .header p {
            color: #8E8E93;
            font-size: 14px;
        }
        .upload-zone {
            border: 2px dashed #48484A;
            border-radius: 16px;
            padding: 40px;
            text-align: center;
            margin: 20px auto;
            max-width: 600px;
            cursor: pointer;
            transition: border-color 0.2s, background 0.2s;
        }
        .upload-zone:hover, .upload-zone.dragover {
            border-color: #0A84FF;
            background: rgba(10, 132, 255, 0.08);
        }
        .upload-zone .icon { font-size: 48px; margin-bottom: 12px; }
        .upload-zone .label { font-size: 16px; color: #8E8E93; }
        .upload-zone input { display: none; }
        .progress-bar {
            width: 100%;
            max-width: 600px;
            margin: 16px auto;
            display: none;
        }
        .progress-bar .track {
            height: 6px;
            background: #2C2C2E;
            border-radius: 3px;
            overflow: hidden;
        }
        .progress-bar .fill {
            height: 100%;
            background: #0A84FF;
            width: 0%;
            transition: width 0.2s;
            border-radius: 3px;
        }
        .progress-bar .text {
            text-align: center;
            font-size: 13px;
            color: #8E8E93;
            margin-top: 6px;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
            gap: 12px;
            max-width: 900px;
            margin: 30px auto;
        }
        .grid-item {
            background: #2C2C2E;
            border-radius: 12px;
            overflow: hidden;
            transition: transform 0.15s;
        }
        .grid-item:hover { transform: scale(1.02); }
        .grid-item .thumb {
            width: 100%;
            aspect-ratio: 1;
            object-fit: cover;
            background: #3A3A3C;
            display: block;
        }
        .grid-item .thumb-placeholder {
            width: 100%;
            aspect-ratio: 1;
            background: #3A3A3C;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 36px;
        }
        .grid-item .info {
            padding: 8px 10px;
        }
        .grid-item .name {
            font-size: 13px;
            font-weight: 500;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        .grid-item .meta {
            font-size: 11px;
            color: #8E8E93;
            margin-top: 2px;
        }
        .grid-item a {
            display: inline-block;
            margin-top: 6px;
            font-size: 12px;
            color: #0A84FF;
            text-decoration: none;
        }
        .grid-item a:hover { text-decoration: underline; }
        .empty {
            text-align: center;
            color: #8E8E93;
            padding: 60px 20px;
            font-size: 15px;
        }
    </style>
    </head>
    <body>
    <div class="header">
        <h1>VaultBox</h1>
        <p>Wi-Fi Transfer</p>
    </div>

    <div class="upload-zone" id="dropZone">
        <div class="icon">&#128228;</div>
        <div class="label">Drop files here or click to upload</div>
        <input type="file" id="fileInput" multiple>
    </div>

    <div class="progress-bar" id="progressBar">
        <div class="track"><div class="fill" id="progressFill"></div></div>
        <div class="text" id="progressText">Uploading...</div>
    </div>

    <div id="grid" class="grid"></div>
    <div id="empty" class="empty" style="display:none;">No files in vault yet.</div>

    <script>
    const dropZone = document.getElementById('dropZone');
    const fileInput = document.getElementById('fileInput');
    const progressBar = document.getElementById('progressBar');
    const progressFill = document.getElementById('progressFill');
    const progressText = document.getElementById('progressText');

    dropZone.addEventListener('click', () => fileInput.click());
    dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.classList.add('dragover'); });
    dropZone.addEventListener('dragleave', () => dropZone.classList.remove('dragover'));
    dropZone.addEventListener('drop', e => {
        e.preventDefault();
        dropZone.classList.remove('dragover');
        uploadFiles(e.dataTransfer.files);
    });
    fileInput.addEventListener('change', () => {
        if (fileInput.files.length) uploadFiles(fileInput.files);
    });

    function uploadFiles(files) {
        const fd = new FormData();
        for (let f of files) fd.append('files', f, f.name);

        const xhr = new XMLHttpRequest();
        const maxUploadMB = \(Constants.wifiTransferMaxRequestBytes / (1024 * 1024));
        progressBar.style.display = 'block';
        progressFill.style.width = '0%';
        progressText.textContent = 'Uploading...';

        xhr.upload.addEventListener('progress', e => {
            if (e.lengthComputable) {
                const pct = Math.round(e.loaded / e.total * 100);
                progressFill.style.width = pct + '%';
                progressText.textContent = pct + '%';
            }
        });

        xhr.addEventListener('load', () => {
            if (xhr.status >= 200 && xhr.status < 300) {
                progressText.textContent = 'Done!';
                setTimeout(() => { progressBar.style.display = 'none'; }, 1500);
                fileInput.value = '';
                loadItems();
                return;
            }

            if (xhr.status === 413) {
                progressText.textContent = 'Video too large. Max upload is ' + maxUploadMB + ' MB.';
            } else {
                const message = (xhr.responseText || '').trim();
                progressText.textContent = message || 'Upload failed.';
            }
        });

        xhr.addEventListener('error', () => {
            progressText.textContent = 'Upload failed.';
        });

        xhr.open('POST', '/upload');
        xhr.send(fd);
    }

    function formatSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / 1048576).toFixed(1) + ' MB';
    }

    function fileIcon(type) {
        if (type === 'video') return '\\u{1F3AC}';
        if (type === 'document') return '\\u{1F4C4}';
        return '\\u{1F5BC}';
    }

    function loadItems() {
        fetch('/api/items')
            .then(r => r.json())
            .then(items => {
                const grid = document.getElementById('grid');
                const empty = document.getElementById('empty');
                grid.innerHTML = '';

                if (!items.length) {
                    empty.style.display = 'block';
                    return;
                }
                empty.style.display = 'none';

                items.forEach(item => {
                    const div = document.createElement('div');
                    div.className = 'grid-item';

                    const hasThumb = item.type === 'photo' || item.type === 'video';
                    const thumbHTML = hasThumb
                        ? '<img class="thumb" src="/thumbnail/' + item.id + '" loading="lazy" onerror="this.outerHTML=\\'<div class=\\\\'thumb-placeholder\\\\'>' + fileIcon(item.type) + '</div>\\';">'
                        : '<div class="thumb-placeholder">' + fileIcon(item.type) + '</div>';

                    div.innerHTML = thumbHTML +
                        '<div class="info">' +
                        '<div class="name">' + item.filename + '</div>' +
                        '<div class="meta">' + formatSize(item.fileSize) + '</div>' +
                        '<a href="/download/' + item.id + '">Download</a>' +
                        '</div>';
                    grid.appendChild(div);
                });
            })
            .catch(() => {});
    }

    loadItems();
    </script>
    </body>
    </html>
    """
}
