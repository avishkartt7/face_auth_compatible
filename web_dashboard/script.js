// Check if user is logged in on page load
window.onload = function() {
    firebase.auth().onAuthStateChanged((user) => {
        if (user) {
            showDashboard();
            showSection('attendance');
        } else {
            showLogin();
        }
    });
};

// Login function
function login() {
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;

    auth.signInWithEmailAndPassword(email, password)
        .then((userCredential) => {
            showDashboard();
            showSection('attendance');
        })
        .catch((error) => {
            alert('Login failed: ' + error.message);
        });
}

// Logout function
function logout() {
    auth.signOut().then(() => {
        showLogin();
    });
}

// Show login page
function showLogin() {
    document.getElementById('loginContainer').style.display = 'flex';
    document.getElementById('dashboardContainer').style.display = 'none';
}

// Show dashboard
function showDashboard() {
    document.getElementById('loginContainer').style.display = 'none';
    document.getElementById('dashboardContainer').style.display = 'flex';
}

// Show different sections with event parameter
function showSection(section, event) {
    // Hide all sections
    document.getElementById('attendanceSection').style.display = 'none';
    document.getElementById('employeesSection').style.display = 'none';
    
    // Remove active class from all nav items
    document.querySelectorAll('.nav-item').forEach(item => {
        item.classList.remove('active');
    });
    
    // Show selected section and set active
    if (section === 'attendance') {
        document.getElementById('attendanceSection').style.display = 'block';
        // Set active class based on whether event exists
        if (event && event.currentTarget) {
            event.currentTarget.classList.add('active');
        } else {
            document.querySelector('.nav-item:nth-child(1)').classList.add('active');
        }
        loadAttendanceData();
        loadEmployeesForFilter();
    } else if (section === 'employees') {
        document.getElementById('employeesSection').style.display = 'block';
        // Set active class based on whether event exists
        if (event && event.currentTarget) {
            event.currentTarget.classList.add('active');
        } else {
            document.querySelector('.nav-item:nth-child(2)').classList.add('active');
        }
        loadEmployees();
    }
}

// Load all attendance data
async function loadAttendanceData() {
    const tbody = document.getElementById('attendanceData');
    tbody.innerHTML = '<tr><td colspan="7">Loading...</td></tr>';

    try {
        const employeesSnapshot = await db.collection('employees').get();
        let allAttendanceData = [];

        for (const employeeDoc of employeesSnapshot.docs) {
            const employeeData = employeeDoc.data();
            const employeeId = employeeDoc.id;

            // Get attendance records for this employee
            const attendanceSnapshot = await db.collection('employees')
                .doc(employeeId)
                .collection('attendance')
                .orderBy('date', 'desc')
                .limit(30)
                .get();

            attendanceSnapshot.docs.forEach(doc => {
                const data = doc.data();
                allAttendanceData.push({
                    employeeName: employeeData.name || 'Unknown',
                    ...data
                });
            });
        }

        // Sort by date descending
        allAttendanceData.sort((a, b) => {
            if (b.date && a.date) {
                return b.date.localeCompare(a.date);
            }
            return 0;
        });

        // Display data
        displayAttendanceData(allAttendanceData);
    } catch (error) {
        console.error('Error loading attendance:', error);
        tbody.innerHTML = '<tr><td colspan="7">Error loading data</td></tr>';
    }
}

// Display attendance data in table
function displayAttendanceData(data) {
    const tbody = document.getElementById('attendanceData');
    
    if (data.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7">No attendance data found</td></tr>';
        return;
    }

    tbody.innerHTML = data.map(record => {
        const checkIn = record.checkIn ? formatTime(record.checkIn) : 'Not checked in';
        const checkOut = record.checkOut ? formatTime(record.checkOut) : 'Not checked out';
        const totalHours = record.totalHours ? record.totalHours.toFixed(2) : '0';
        const status = record.workStatus || 'Pending';
        const statusClass = status === 'Completed' ? 'status-completed' : 'status-progress';

        return `
            <tr>
                <td>${record.employeeName}</td>
                <td>${record.date || ''}</td>
                <td>${checkIn}</td>
                <td>${checkOut}</td>
                <td>${totalHours} hrs</td>
                <td class="${statusClass}">${status}</td>
                <td>${record.location || 'Unknown'}</td>
            </tr>
        `;
    }).join('');
}

// Format timestamp to readable time
// Update the displayAttendanceData function in script.js
function displayAttendanceData(data) {
    const tbody = document.getElementById('attendanceData');
    
    if (data.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7">No attendance data found</td></tr>';
        return;
    }

    tbody.innerHTML = data.map(record => {
        const checkIn = record.checkIn ? formatTime(record.checkIn) : 'Not checked in';
        const checkOut = record.checkOut ? formatTime(record.checkOut) : 'Not checked out';
        
        // Calculate total hours properly
        let totalHoursFormatted = '0.00';
        if (record.checkIn && record.checkOut) {
            const hoursFormatted = calculateTotalHours(record.checkIn, record.checkOut);
            totalHoursFormatted = hoursFormatted;
        } else if (record.totalHours) {
            // If totalHours is stored as decimal hours, convert to HH:MM format
            totalHoursFormatted = convertDecimalToTime(record.totalHours);
        }
        
        const status = record.workStatus || 'Pending';
        const statusClass = status === 'Completed' ? 'status-completed' : 'status-progress';

        return `
            <tr>
                <td>${record.employeeName}</td>
                <td>${record.date || ''}</td>
                <td>${checkIn}</td>
                <td>${checkOut}</td>
                <td>${totalHoursFormatted}</td>
                <td class="${statusClass}">${status}</td>
                <td>${record.location || 'Unknown'}</td>
            </tr>
        `;
    }).join('');
}

// Add this new function to calculate total hours in HH:MM format
function calculateTotalHours(checkIn, checkOut) {
    let checkInDate, checkOutDate;
    
    // Handle Firestore Timestamp objects
    if (checkIn && checkIn.toDate) {
        checkInDate = checkIn.toDate();
    } else if (checkIn && checkIn.seconds) {
        // Handle Firestore Timestamp with seconds property
        checkInDate = new Date(checkIn.seconds * 1000 + (checkIn.nanoseconds || 0) / 1000000);
    } else if (typeof checkIn === 'string') {
        checkInDate = new Date(checkIn);
    } else {
        return '0:00';
    }
    
    if (checkOut && checkOut.toDate) {
        checkOutDate = checkOut.toDate();
    } else if (checkOut && checkOut.seconds) {
        // Handle Firestore Timestamp with seconds property
        checkOutDate = new Date(checkOut.seconds * 1000 + (checkOut.nanoseconds || 0) / 1000000);
    } else if (typeof checkOut === 'string') {
        checkOutDate = new Date(checkOut);
    } else {
        return '0:00';
    }
    
    // Calculate difference in milliseconds
    const diffMs = checkOutDate - checkInDate;
    
    // Convert to total minutes and round properly
    const totalMinutes = Math.round(diffMs / (1000 * 60));
    
    // Convert to hours and minutes
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    
    // Format as HH:MM
    return `${hours}:${minutes.toString().padStart(2, '0')}`;
}

// Convert decimal hours to HH:MM format
function convertDecimalToTime(decimalHours) {
    // Convert decimal hours to total minutes
    const totalMinutes = Math.round(decimalHours * 60);
    
    // Calculate hours and minutes
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    
    // Format as HH:MM
    return `${hours}:${minutes.toString().padStart(2, '0')}`;
}

// Update the formatTime function to handle both timestamps and strings better
function formatTime(timestamp) {
    let date;
    
    if (timestamp && timestamp.toDate) {
        date = timestamp.toDate();
    } else if (timestamp && typeof timestamp === 'string') {
        // Handle ISO string format
        if (timestamp.includes('T')) {
            date = new Date(timestamp);
        } else {
            // Handle the specific format from your data: "2025-05-10T22:14:40.373411"
            date = new Date(timestamp.replace(' ', 'T'));
        }
    } else {
        return timestamp;
    }
    
    if (date && !isNaN(date)) {
        return date.toLocaleTimeString('en-US', { 
            hour: '2-digit', 
            minute: '2-digit',
            hour12: true
        });
    }
    
    return timestamp;
}

// Load employees for filter dropdown
async function loadEmployeesForFilter() {
    const select = document.getElementById('employeeFilter');
    select.innerHTML = '<option value="">All Employees</option>';
    
    try {
        const snapshot = await db.collection('employees').get();
        
        snapshot.docs.forEach(doc => {
            const employee = doc.data();
            const option = document.createElement('option');
            option.value = doc.id;
            option.textContent = employee.name || 'Unknown';
            select.appendChild(option);
        });
    } catch (error) {
        console.error('Error loading employees for filter:', error);
    }
}

// Load employees for management
async function loadEmployees() {
    const tbody = document.getElementById('employeeData');
    tbody.innerHTML = '<tr><td colspan="7">Loading...</td></tr>';

    try {
        const snapshot = await db.collection('employees').get();
        const employees = [];

        snapshot.docs.forEach(doc => {
            const data = doc.data();
            employees.push({
                id: doc.id,
                ...data
            });
        });

        displayEmployees(employees);
    } catch (error) {
        console.error('Error loading employees:', error);
        tbody.innerHTML = '<tr><td colspan="7">Error loading employees</td></tr>';
    }
}

// Display employees in table
function displayEmployees(employees) {
    const tbody = document.getElementById('employeeData');
    
    if (employees.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7">No employees found</td></tr>';
        return;
    }

    tbody.innerHTML = employees.map(emp => {
        const status = emp.registrationCompleted ? 'Active' : 'Pending';
        const statusClass = emp.registrationCompleted ? 'status-active' : 'status-pending';

        return `
            <tr>
                <td>${emp.pin || 'N/A'}</td>
                <td>${emp.name || 'N/A'}</td>
                <td>${emp.designation || 'N/A'}</td>
                <td>${emp.department || 'N/A'}</td>
                <td>${emp.email || 'N/A'}</td>
                <td class="${statusClass}">${status}</td>
                <td>
                    <button onclick="deleteEmployee('${emp.id}')" class="btn-small btn-danger">Delete</button>
                </td>
            </tr>
        `;
    }).join('');
}

// Show add employee modal
function showAddEmployeeModal() {
    document.getElementById('addEmployeeModal').style.display = 'block';
    document.getElementById('employeeForm').reset();
}

// Close modal
function closeModal() {
    document.getElementById('addEmployeeModal').style.display = 'none';
}

// Generate random PIN
function generateRandomPIN() {
    return Math.floor(1000 + Math.random() * 9000).toString();
}

// Setup form submission listener after DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    // Handle form submission
    const employeeForm = document.getElementById('employeeForm');
    if (employeeForm) {
        employeeForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            
            const employeeData = {
                pin: document.getElementById('empPin').value,
                name: document.getElementById('empName').value,
                designation: document.getElementById('empDesignation').value,
                department: document.getElementById('empDepartment').value,
                email: document.getElementById('empEmail').value || '',
                phone: document.getElementById('empPhone').value || '',
                country: document.getElementById('empCountry').value || '',
                birthdate: document.getElementById('empBirthdate').value || '',
                registrationCompleted: false,
                profileCompleted: false,
                faceRegistered: false,
                createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                lastUpdated: firebase.firestore.FieldValue.serverTimestamp()
            };

            try {
                // Check if PIN already exists
                const pinCheck = await db.collection('employees')
                    .where('pin', '==', employeeData.pin)
                    .get();

                if (!pinCheck.empty) {
                    alert('This PIN is already in use. Please use a different PIN.');
                    return;
                }

                // Add employee to Firestore
                await db.collection('employees').add(employeeData);
                
                alert('Employee added successfully!');
                closeModal();
                loadEmployees();
            } catch (error) {
                console.error('Error adding employee:', error);
                alert('Error adding employee: ' + error.message);
            }
        });
    }
});

// Delete employee
async function deleteEmployee(employeeId) {
    if (confirm('Are you sure you want to delete this employee?')) {
        try {
            await db.collection('employees').doc(employeeId).delete();
            alert('Employee deleted successfully');
            loadEmployees();
        } catch (error) {
            console.error('Error deleting employee:', error);
            alert('Error deleting employee: ' + error.message);
        }
    }
}

// Filter by date
function filterByDate() {
    const selectedDate = document.getElementById('dateFilter').value;
    loadFilteredData({ date: selectedDate });
}

// Filter by employee
function filterByEmployee() {
    const selectedEmployee = document.getElementById('employeeFilter').value;
    loadFilteredData({ employeeId: selectedEmployee });
}

// Load filtered data
async function loadFilteredData(filters = {}) {
    const tbody = document.getElementById('attendanceData');
    tbody.innerHTML = '<tr><td colspan="7">Loading...</td></tr>';

    try {
        let allAttendanceData = [];

        if (filters.employeeId) {
            // Load data for specific employee
            const employeeDoc = await db.collection('employees').doc(filters.employeeId).get();
            const employeeData = employeeDoc.data();

            let query = db.collection('employees')
                .doc(filters.employeeId)
                .collection('attendance');

            if (filters.date) {
                query = query.where('date', '==', filters.date);
            }

            const snapshot = await query.orderBy('date', 'desc').get();

            snapshot.docs.forEach(doc => {
                const data = doc.data();
                allAttendanceData.push({
                    employeeName: employeeData.name || 'Unknown',
                    ...data
                });
            });
        } else if (filters.date) {
            // Load all employees data for specific date
            const employeesSnapshot = await db.collection('employees').get();

            for (const employeeDoc of employeesSnapshot.docs) {
                const employeeData = employeeDoc.data();
                const employeeId = employeeDoc.id;

                const attendanceSnapshot = await db.collection('employees')
                    .doc(employeeId)
                    .collection('attendance')
                    .where('date', '==', filters.date)
                    .get();

                attendanceSnapshot.docs.forEach(doc => {
                    const data = doc.data();
                    allAttendanceData.push({
                        employeeName: employeeData.name || 'Unknown',
                        ...data
                    });
                });
            }
        } else {
            // Load all data
            await loadAttendanceData();
            return;
        }

        displayAttendanceData(allAttendanceData);
    } catch (error) {
        console.error('Error loading filtered data:', error);
        tbody.innerHTML = '<tr><td colspan="7">Error loading data</td></tr>';
    }
}

// Handle Excel upload
function handleExcelUpload(event) {
    const file = event.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async (e) => {
        try {
            const data = new Uint8Array(e.target.result);
            const workbook = XLSX.read(data, { type: 'array' });
            const firstSheet = workbook.Sheets[workbook.SheetNames[0]];
            const jsonData = XLSX.utils.sheet_to_json(firstSheet);

            // Process each row
            let successCount = 0;
            let errorCount = 0;

            for (const row of jsonData) {
                try {
                    const employeeData = {
                        pin: row.PIN?.toString() || generateRandomPIN(),
                        name: row.Name || '',
                        designation: row.Designation || '',
                        department: row.Department || '',
                        email: row.Email || '',
                        phone: row.Phone?.toString() || '',
                        country: row.Country || '',
                        birthdate: row.Birthdate || '',
                        registrationCompleted: false,
                        profileCompleted: false,
                        faceRegistered: false,
                        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                        lastUpdated: firebase.firestore.FieldValue.serverTimestamp()
                    };

                    // Check for duplicate PIN
                    const pinCheck = await db.collection('employees')
                        .where('pin', '==', employeeData.pin)
                        .get();

                    if (pinCheck.empty) {
                        await db.collection('employees').add(employeeData);
                        successCount++;
                    } else {
                        errorCount++;
                        console.log(`PIN ${employeeData.pin} already exists`);
                    }
                } catch (err) {
                    errorCount++;
                    console.error('Error processing row:', err);
                }
            }

            alert(`Import completed!\nSuccess: ${successCount}\nErrors: ${errorCount}`);
            loadEmployees();
        } catch (error) {
            console.error('Error reading Excel file:', error);
            alert('Error reading Excel file: ' + error.message);
        }
    };

    reader.readAsArrayBuffer(file);
}

// Download Excel template
function downloadTemplate() {
    // Create template data
    const templateData = [
        {
            PIN: "1234",
            Name: "John Doe",
            Designation: "Software Developer",
            Department: "IT Department",
            Email: "john@example.com",
            Phone: "+971501234567",
            Country: "UAE",
            Birthdate: "01/01/1990"
        }
    ];

    // Create workbook
    const ws = XLSX.utils.json_to_sheet(templateData);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, "Employees");

    // Download file
    XLSX.writeFile(wb, "employee_template.xlsx");
}