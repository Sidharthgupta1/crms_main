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

// A table/bgcolor-based "bulletproof" button instead of a plain styled <a>.
// Outlook's dark mode recolors plain link text to its own blue regardless of
// inline `color` CSS (even with !important) — but it reliably respects the
// legacy `bgcolor` HTML attribute and an inner <span> with an explicit
// color, which this uses for both the pill background and the white label.
function actionButton(link, label, color) {
  if (!link) return '';
  const bg = color || '#003366';
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin-top:16px;"><tr>
<td bgcolor="${bg}" style="border-radius:4px;">
<a href="${link}" target="_blank" style="display:inline-block;padding:10px 24px;font-family:Segoe UI,Arial,sans-serif;font-size:14px;font-weight:600;text-decoration:none;border-radius:4px;"><span style="color:#ffffff;">${label}</span></a>
</td>
</tr></table>`;
}

// A row of buttons (e.g. Approve + Reject) side by side, same bulletproof
// bgcolor/span pattern as actionButton, with a gap between cells.
function actionButtonRow(buttons) {
  const cells = buttons.filter(b => b.link).map(b =>
    `<td bgcolor="${b.color}" style="border-radius:4px;">
<a href="${b.link}" target="_blank" style="display:inline-block;padding:10px 24px;font-family:Segoe UI,Arial,sans-serif;font-size:14px;font-weight:600;text-decoration:none;border-radius:4px;"><span style="color:#ffffff;">${b.label}</span></a>
</td>
<td style="width:12px;"></td>`
  ).join('');
  if (!cells) return '';
  return `<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin-top:16px;"><tr>${cells}</tr></table>`;
}

// Resource Bandwidth digest — a week-view and a month-view heatmap table,
// same 4-color status scheme (green/amber/coral/red) as the in-app view.
// Uses bgcolor HTML attributes on the cells rather than CSS background —
// the same Outlook-dark-mode workaround as the bulletproof buttons above.
function bwStatusColor(n) {
  if (n === 0) return { bg: '#0ca30c', fg: '#ffffff' };
  if (n <= 2)  return { bg: '#fab219', fg: '#3d2e00' };
  if (n <= 4)  return { bg: '#ec835a', fg: '#ffffff' };
  return { bg: '#d03b3b', fg: '#ffffff' };
}
function bwHeatTable(buckets, resources, counts) {
  const head = '<th style="text-align:left;padding:6px 10px;border-bottom:1px solid #ddd;font-size:12px;color:#666">Resource</th>' +
    buckets.map(b => `<th style="text-align:center;padding:6px 10px;border-bottom:1px solid #ddd;font-size:12px;color:#666">${b.label}<br><span style="font-weight:400;color:#999">${b.range}</span></th>`).join('');
  const rows = resources.map(r => {
    const cells = counts(r).map(n => {
      const c = bwStatusColor(n);
      return `<td style="text-align:center;padding:8px;border-bottom:1px solid #eee;"><span bgcolor="${c.bg}" style="display:inline-block;min-width:24px;padding:3px 8px;border-radius:6px;background:${c.bg};color:${c.fg};font-size:13px;font-weight:600;">${n}</span></td>`;
    }).join('');
    return `<tr><td style="padding:8px 10px;border-bottom:1px solid #eee;font-size:13px;">${r.name}</td>${cells}</tr>`;
  }).join('');
  return `<table style="width:100%;border-collapse:collapse;margin-bottom:16px;"><thead><tr>${head}</tr></thead><tbody>${rows}</tbody></table>`;
}
function bandwidthDigestTemplate(data) {
  const legend = `<p style="font-size:12px;color:#888;margin:0 0 20px;">
<span style="background:#0ca30c;color:#fff;padding:2px 8px;border-radius:8px;">Free 0</span>
&nbsp;<span style="background:#fab219;color:#3d2e00;padding:2px 8px;border-radius:8px;">Moderate 1-2</span>
&nbsp;<span style="background:#ec835a;color:#fff;padding:2px 8px;border-radius:8px;">Loaded 3-4</span>
&nbsp;<span style="background:#d03b3b;color:#fff;padding:2px 8px;border-radius:8px;">Overloaded 5+</span></p>`;
  const body = `<p>Open FSD, Testing and UAT tasks only — projected resource load by week and by month.</p>
<p style="font-weight:600;margin-bottom:8px;">Week view</p>
${bwHeatTable(data.weekBuckets, data.resources, r => r.weekCounts)}
<p style="font-weight:600;margin-bottom:8px;">Month view</p>
${bwHeatTable(data.monthBuckets, data.resources, r => r.monthCounts)}
${legend}
${actionButton(data.link, 'Open Resource Report')}`;
  return buildBaseHtml('Resource Bandwidth Digest', body);
}

// Title row is shown whenever data.title is present — used across every
// template (assignment, approval, completion, defaulted) per business
// request: "add the Title on it on each and every mail."
function titleRow(data) {
  return data.title ? [{ label: 'Title', value: data.title }] : [];
}

// CR Owner row — shown whenever data.crOwner is present. emailService.js only
// populates crOwner from FSD onward (per business rule: CR Owner isn't set
// during RD, and the CC-to-CR-Owner behavior only starts at FSD), so this
// naturally stays blank on RD-phase mail without any template-level logic.
function crOwnerRow(data) {
  return data.crOwner ? [{ label: 'CR Owner', value: data.crOwner }] : [];
}

function phaseStartedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    ...titleRow(data),
    ...crOwnerRow(data),
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-blue">${data.phase}</span>` },
    { label: 'Status', value: 'In Progress' },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${actionButton(data.link, 'View CR in System')}`;
  return buildBaseHtml(`${data.phase} Phase Started`, body);
}

function approvalRequiredTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    ...titleRow(data),
    ...crOwnerRow(data),
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-orange">${data.phase}</span>` },
    { label: 'Level', value: `Level ${data.level}` },
    { label: 'Requested By', value: data.requesterName },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${actionButtonRow([
    { link: data.approveLink, label: 'Approve', color: '#2e7d32' },
    { link: data.rejectLink, label: 'Reject', color: '#c62828' },
  ])}
${data.link ? `<p style="margin-top:16px;font-size:12px;"><a href="${data.link}" style="color:#003366;">Or open this CR in CRMS to review details first</a></p>` : ''}`;
  return buildBaseHtml(`Action Required - ${data.phase} Approval`, body);
}

function approvalCompletedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    ...titleRow(data),
    ...crOwnerRow(data),
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-green">${data.phase}</span>` },
    { label: 'Level', value: `Level ${data.level}` },
    { label: 'Approved By', value: data.approvedBy },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${actionButton(data.link, 'View CR')}`;
  return buildBaseHtml(`${data.phase} Level ${data.level} Approved`, body);
}

function approvalRejectedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    ...titleRow(data),
    ...crOwnerRow(data),
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-red">${data.phase}</span>` },
    { label: 'Rejected By', value: data.rejectedBy },
    { label: 'Remarks', value: data.remarks },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${actionButton(data.link, 'View CR')}`;
  return buildBaseHtml(`${data.phase} Approval Rejected`, body);
}

function phaseCompletedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    ...titleRow(data),
    ...crOwnerRow(data),
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-green">${data.phase}</span>` },
    { label: 'Status', value: 'Completed' },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${actionButton(data.link, 'View CR')}`;
  return buildBaseHtml(`${data.phase} Phase Completed`, body);
}

function subtaskAssignedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    ...titleRow(data),
    ...crOwnerRow(data),
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-blue">${data.phase}</span>` },
    { label: 'Task', value: data.taskNumber },
    { label: 'Assigned By', value: data.assignedBy },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${actionButton(data.link, 'View Task')}`;
  return buildBaseHtml('Sub-Task Assigned', body);
}

function subtaskCompletedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    ...titleRow(data),
    ...crOwnerRow(data),
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-green">${data.phase}</span>` },
    { label: 'Task', value: data.taskNumber },
    { label: 'Completed By', value: data.completedBy },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${actionButton(data.link, 'View CR')}`;
  return buildBaseHtml('Sub-Task Completed', body);
}

function assignmentTemplate(data) {
  // Exact wording per business request: kind is 'CR' or 'SUB-TASK', number is
  // the CR/task number. Kept verbatim as the lead line. taskType/assignedBy/
  // assignedDate are SUB-TASK-only fields (a CR has no "type" or single
  // "assigned by" actor the same way a sub-task does).
  const rows = [
    { label: data.kind === 'CR' ? 'CR Number' : 'Task Number', value: data.number },
    ...(data.kind === 'SUB-TASK' && data.parentRelease ? [{ label: 'Parent Release', value: data.parentRelease }] : []),
    ...titleRow(data),
    ...(data.kind === 'SUB-TASK' && data.taskType ? [{ label: 'Type of Task', value: data.taskType }] : []),
    ...(data.kind === 'SUB-TASK' && data.assignedBy ? [{ label: 'Assigned By', value: data.assignedBy }] : []),
    ...(data.kind === 'SUB-TASK' && data.assignedDate ? [{ label: 'Assigned Date', value: data.assignedDate }] : []),
    ...crOwnerRow(data),
  ];
  const body = `<p>The ${data.kind} ${data.number} IS ASSIGN TO YOU.</p>
${detailsTable(rows)}
${actionButton(data.link, 'Click here to open it')}
<p style="margin-top:24px;font-size:12px;color:#888;">For any support contact <a href="mailto:Sidharth.Gupta@motherson.com">Sidharth.Gupta@motherson.com</a>.</p>`;
  return buildBaseHtml(`${data.kind} ${data.number} IS ASSIGN TO YOU.`, body);
}

function taskDefaultedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    ...titleRow(data),
    ...crOwnerRow(data),
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-red">${data.phase}</span>` },
    { label: 'Task', value: data.taskNumber },
    { label: 'Days Overdue', value: `<span class="badge badge-orange">${data.ageingDays} days</span>` },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${actionButton(data.link, 'View Task')}`;
  return buildBaseHtml('Task Overdue - Action Needed', body);
}

function deploymentCompletedTemplate(data) {
  const rows = [
    { label: 'CR Number', value: data.crNumber },
    ...titleRow(data),
    ...crOwnerRow(data),
    { label: 'Module', value: data.moduleName },
    { label: 'Phase', value: `<span class="badge badge-green">Deployment</span>` },
    { label: 'Status', value: 'Completed' },
    { label: 'Date & Time', value: data.timestamp },
  ];
  const body = `<p>Dear ${data.recipientName},</p>
<p>${data.message}</p>
${detailsTable(rows)}
${actionButton(data.link, 'View CR')}`;
  return buildBaseHtml('Deployment Completed', body);
}

module.exports = {
  phaseStartedTemplate, approvalRequiredTemplate, approvalCompletedTemplate,
  approvalRejectedTemplate, phaseCompletedTemplate, subtaskAssignedTemplate,
  subtaskCompletedTemplate, deploymentCompletedTemplate,
  taskDefaultedTemplate, assignmentTemplate, bandwidthDigestTemplate,
};
