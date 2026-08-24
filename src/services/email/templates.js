'use strict';

function buildBaseHtml(title, bodyHtml) {
  return `<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><style>
body{font-family:Segoe UI,Arial,sans-serif;margin:0;padding:0;background:#f5f5f5}
.container{max-width:600px;margin:20px auto;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.1)}
.header{background:#003366;color:#fff;padding:20px 24px}
.header h1{margin:0;font-size:20px;font-weight:600}
.body{padding:24px}
.footer{padding:16px 24px;background:#f9f9f9;font-size:12px;color:#888;border-top:1px solid #e0e0e0}
table.details{width:100%;border-collapse:collapse}
table.details td{padding:8px 12px;border-bottom:1px solid #eee;font-size:14px}
table.details td.label{color:#666;font-weight:600;width:120px;vertical-align:top}
.badge{display:inline-block;padding:4px 12px;border-radius:12px;font-size:12px;font-weight:600}
.badge-blue{background:#e3f2fd;color:#1565c0}
.badge-green{background:#e8f5e9;color:#2e7d32}
.badge-red{background:#ffebee;color:#c62828}
.badge-orange{background:#fff3e0;color:#e65100}
.btn{display:inline-block;padding:10px 24px;background:#003366;color:#fff!important;text-decoration:none;border-radius:4px;font-size:14px;margin-top:16px}
</style></head>
<body>
<div class="container">
<div class="header"><h1>${title}</h1></div>
<div class="body">${bodyHtml}</div>
<div class="footer">
  <p style="margin:0 0 4px">This is an automated notification from the CRMS system.</p>
  <p style="margin:0">© ${new Date().getFullYear()} Motherson CRMS</p>
</div>
</div>
</body>
</html>`;
}

function detailsTable(rows) {
  if (!rows || !rows.length) return '';
  return `<table class="details">${rows.map(r =>
    `<tr><td class="label">${r.label}</td><td>${r.value}</td></tr>`
  ).join('')}</table>`;
}

function phaseStartedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-blue">${data.phase}</span>` },
    { label: 'Status', value: 'In Progress' },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${data.link ? `<a href="${data.link}" class="btn">View CR in System</a>` : ''}`;
  return buildBaseHtml(`${data.phase} Phase Started`, body);
}

function approvalRequiredTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-orange">${data.phase}</span>` },
    { label: 'Level', value: `Level ${data.level}` },
    { label: 'Requested By', value: data.requesterName },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${data.link ? `<a href="${data.link}" class="btn">Review & Approve</a>` : ''}`;
  return buildBaseHtml(`Action Required - ${data.phase} Approval`, body);
}

function approvalCompletedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-green">${data.phase}</span>` },
    { label: 'Level', value: `Level ${data.level}` },
    { label: 'Approved By', value: data.approvedBy },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${data.link ? `<a href="${data.link}" class="btn">View CR</a>` : ''}`;
  return buildBaseHtml(`${data.phase} Level ${data.level} Approved`, body);
}

function approvalRejectedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-red">${data.phase}</span>` },
    { label: 'Rejected By', value: data.rejectedBy },
    { label: 'Remarks', value: data.remarks },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${data.link ? `<a href="${data.link}" class="btn">View CR</a>` : ''}`;
  return buildBaseHtml(`${data.phase} Approval Rejected`, body);
}

function phaseCompletedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-green">${data.phase}</span>` },
    { label: 'Status', value: 'Completed' },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${data.link ? `<a href="${data.link}" class="btn">View CR</a>` : ''}`;
  return buildBaseHtml(`${data.phase} Phase Completed`, body);
}

function subtaskAssignedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-blue">${data.phase}</span>` },
    { label: 'Task', value: data.taskNumber },
    { label: 'Description', value: data.taskDescription },
    { label: 'Assigned By', value: data.assignedBy },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${data.link ? `<a href="${data.link}" class="btn">View Task</a>` : ''}`;
  return buildBaseHtml('Sub-Task Assigned', body);
}

function subtaskCompletedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-green">${data.phase}</span>` },
    { label: 'Task', value: data.taskNumber },
    { label: 'Completed By', value: data.completedBy },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${data.link ? `<a href="${data.link}" class="btn">View CR</a>` : ''}`;
  return buildBaseHtml('Sub-Task Completed', body);
}

function deploymentCompletedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-green">Deployment</span>` },
    { label: 'Status', value: 'Completed' },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${data.link ? `<a href="${data.link}" class="btn">View CR</a>` : ''}`;
  return buildBaseHtml('Deployment Completed', body);
}

module.exports = {
  phaseStartedTemplate, approvalRequiredTemplate, approvalCompletedTemplate,
  approvalRejectedTemplate, phaseCompletedTemplate, subtaskAssignedTemplate,
  subtaskCompletedTemplate, deploymentCompletedTemplate,
};