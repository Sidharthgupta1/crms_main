// ════════════════════════════════════════════════════════════════════════
// DBA Deployment — New sub-phase between Sub-Tasks and Comments
// ════════════════════════════════════════════════════════════════════════
async function renderDBADeployment(data) {
  const container = document.getElementById('dba-container');
  if (!container) return;

  // Filter only DBA_DEPLOYMENT tasks
  const dbaTasks = (data.tasks || []).filter(t => t.phaseCode === 'DBA_DEPLOYMENT');

  // Mandatory warning logic
  if (dbaTasks.length === 0) {
    container.innerHTML = `
      <div style="padding:16px;background:#fef2f2;border:1px solid #fca5a5;border-radius:8px;color:#991b1b;margin:8px 0">
        <div style="font-weight:600;margin-bottom:8px">⚠️ DBA Deployment Sub-Task Required</div>
        <div style="font-size:13px;line-height:1.5">
          Before you can advance this Release to <strong>Closed</strong>, you must create at least one <strong>DBA Deployment sub-task</strong>.
          This ensures critical database changes are planned, implemented, and validated before release.
        </div>
        <div style="margin-top:12px">
          <button class="btn btn-red btn-sm" onclick="openAddDBASubTask()">+ Add DBA Deployment Sub-Task</button>
        </div>
      </div>
    `;
    return;
  }

  // Build table
  const hasOpen = dbaTasks.some(t => t.state === 'Open');
  const mandatoryWarning = hasOpen
    ? `
      <div style="padding:8px;background:#fef3c7;border:1px solid #fcd34d;border-radius:6px;color:#92400e;margin:8px 0;font-size:12px">
        ⚠️ <strong>Blocking:</strong> You cannot advance this Release to <strong>Closed</strong> until all DBA Deployment sub-tasks are completed.
      </div>
    `
    : '';

  container.innerHTML = `
    ${mandatoryWarning}
    <div class="table-toolbar" style="padding:8px 0;margin-bottom:8px">
      <button class="btn btn-red btn-sm" onclick="openAddDBASubTask()">+ Add DBA Deployment Sub-Task</button>
    </div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Number</th>
            <th>Type</th>
            <th>State</th>
            <th>Description</th>
            <th>Group</th>
            <th>Assigned To</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          ${dbaTasks.map(t => `
            <tr>
              <td>${t.taskNumber}</td>
              <td>DBA Deployment Task</td>
              <td>${stateBadge(t.state)}</td>
              <td>${t.shortDescription}</td>
              <td>${t.groupName || '—'}</td>
              <td>${t.assignedTo || '—'}</td>
              <td>
                ${t.state === 'Open'
                  ? `<button class="btn btn-outline btn-sm" onclick="openEditTask('${t.taskId}')">Edit</button>
                     <button class="btn btn-green btn-sm" onclick="closeDBATask('${t.taskId}')">Close</button>`
                  : `<span style="color:var(--grey-400);font-size:12px">Closed</span>`
                }
              </td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    </div>
  `;
}

async function renderDBADeploymentById(id) {
  try {
    const [r, tasks] = await Promise.all([
      GET(`/releases/${id}`),
      GET(`/releases/${id}/tasks`), // Fetch all tasks
    ]);
    renderDBADeployment({ release: r, tasks });
  } catch(err) {
    console.error('Failed to render DBA Deployment tab:', err);
  }
}

function openAddDBASubTask() {
  openModal('task-modal');
  // Hard-code values for DBA Deployment
  document.getElementById('task-modal-title').textContent = 'Add DBA Deployment Task';
  document.getElementById('t-number').value = '(auto-generated)';
  document.getElementById('t-type').value = 'DBA Deployment Task';
  document.getElementById('t-desc').value = '';
  document.getElementById('t-ag').innerHTML = '<option value="">— Select group —</option>' + REF.groups.map(g => `<option value="${g.groupId}">${g.groupName}</option>`).join('');
  document.getElementById('t-at').innerHTML = '<option value="">— Select —</option>';
  // Set phase code to DBA_DEPLOYMENT
  window.activeTaskPhase = 'DBA_DEPLOYMENT';
}

function closeDBATask(taskId) {
  showConfirmModal(
    'Close DBA Deployment Sub-Task',
    '<p>Are you sure you want to close this DBA Deployment sub-task? Once closed, it cannot be reopened.</p>',
    'Close',
    'var(--green)',
    () => { PATCH(`/releases/${activeDetailId}/tasks/${taskId}/close`, {}).then(() => {
      renderDBADeploymentById(activeDetailId);
      renderSubTasksById(activeDetailId);
      toast('DBA Deployment sub-task closed', false, 'green');
    }); }
  );
}

function openEditTask(taskId) {
  showInputModal('Edit DBA Deployment Sub-Task', 'Edit functionality coming soon', true);
}