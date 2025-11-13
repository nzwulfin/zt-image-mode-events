document.addEventListener('DOMContentLoaded', function() {

    const loadingSpinner = document.getElementById('loading-spinner');
    const lastUpdatedEl = document.getElementById('last-updated');

    const osDetailsContainer = document.getElementById('os-details-container');
    const pythonPackagesTbody = document.getElementById('python-packages-tbody');
    const systemPackagesTbody = document.getElementById('system-packages-tbody');
    const systemOsIdEl = document.getElementById('system-os-id');

    // Function to create a detail item for the OS card
    function createOsDetailItem(icon, label, value) {
        // Use a placeholder if value is missing or empty
        const displayValue = value || 'N/A';
        return `
            <div class="col-md-6 col-lg-4 mb-3">
                <div class="d-flex align-items-center">
                    <i class="bi ${icon} fs-4 me-3 text-info"></i>
                    <div>
                        <strong class="d-block text-muted">${label}</strong>
                        <span class="fs-6">${displayValue}</span>
                    </div>
                </div>
            </div>
        `;
    }
    
    // Function to render a row in a package table
    function renderPackageRow(pkg) {
        const isNotFound = pkg.version.includes('Not Found') || pkg.version.includes('Error');
        const rowClass = isNotFound ? 'text-danger fst-italic' : '';
        const version = isNotFound ? `<em>${pkg.version}</em>` : pkg.version;

        return `<tr class="${rowClass}"><td>${pkg.name}</td><td>${version}</td></tr>`;
    }

    async function updateData() {
        loadingSpinner.classList.remove('d-none'); // Show spinner

        try {
            const response = await fetch('/data');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const data = await response.json();

            // 1. Update "Last Updated" timestamp
            lastUpdatedEl.textContent = data.last_updated;

            // 2. Update OS Details Card
            const os = data.os_details;
            osDetailsContainer.innerHTML = `
                ${createOsDetailItem('bi-hdd-stack', 'Hostname', os.node)}
                ${createOsDetailItem('bi-columns-gap', 'System', os.system)}
                ${createOsDetailItem('bi-cassette', 'Distribution', os.distro_name)}
                ${createOsDetailItem('bi-ticket-detailed', 'Kernel Release', os.release)}
                ${createOsDetailItem('bi-gear-wide-connected', 'Kernel Version', os.version)}
                ${createOsDetailItem('bi-cpu', 'Processor', os.processor)}
                ${createOsDetailItem('bi-motherboard', 'Architecture', os.machine)}
		${createOsDetailItem('bi-stopwatch', 'System Uptime', os.uptime)}
		${createOsDetailItem('bi-clipboard2-heart-fill', 'Operating Mode', os.mode)}

            `;

            // 3. Update Python Packages Table
            pythonPackagesTbody.innerHTML = data.python_packages.map(renderPackageRow).join('');

            // 4. Update System Packages Table
            systemOsIdEl.textContent = os.distro_id || 'Unknown OS';
            systemPackagesTbody.innerHTML = data.system_packages.map(renderPackageRow).join('');

        } catch (error) {
            console.error("Failed to fetch data:", error);
            // Optionally, display an error message on the page
            lastUpdatedEl.textContent = 'Error fetching data';
        } finally {
            loadingSpinner.classList.add('d-none'); // Hide spinner
        }
    }

    // Initial data load
    updateData();

    // Set interval to refresh data every 5 seconds (5000 milliseconds)
    setInterval(updateData, 5000);
});
