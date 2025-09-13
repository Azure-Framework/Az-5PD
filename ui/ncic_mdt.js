// NCIC MDT - NUI JavaScript (standalone file)
// Save as ncic_mdt.js and include in your HTML with <script src="ncic_mdt.js"></script>
// Handles: sendUI, tabs, close, plate/id lookups (NetID or "First Last"), history selects,
// NUI message handling for populate, plateResult, idResult, and list population.

(function() {
  // Send to client (FiveM NUI -> client.lua)
  function sendUI(event, data) {
    fetch(`https://${GetParentResourceName()}/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data||{})
    }).catch(e => {
      // swallow fetch errors (NUI may be running outside game during dev)
      console.warn('sendUI error', e);
    });
  }

  // --- DOM refs ---
  const app             = document.getElementById('app');
  const btnClose        = document.getElementById('btn-close');

  const plateInput      = document.getElementById('plate-input');
  const plateHistorySel = document.getElementById('plate-history');
  const btnPlate        = document.getElementById('btn-plate');
  const plateStatus     = document.getElementById('plate-status');
  const plateIndicator  = document.getElementById('plate-status-indicator');

  const idInput         = document.getElementById('id-input');
  const idHistorySel    = document.getElementById('id-history');
  const btnId           = document.getElementById('btn-id');
  const idResults       = document.getElementById('id-results');
  const idIndicator     = document.getElementById('id-status-indicator');

  // --- Tabs ---
  document.querySelectorAll('nav button').forEach(btn=>{
    btn.addEventListener('click',()=>{
      document.querySelectorAll('nav button').forEach(b=>b.classList.remove('active'));
      document.querySelectorAll('.panel').forEach(p=>p.classList.remove('active'));
      btn.classList.add('active');
      const panel = document.getElementById('panel-'+btn.dataset.tab);
      if(panel) panel.classList.add('active');
    });
  });

  // --- Close handlers ---
  if(btnClose) btnClose.onclick = () => sendUI('escape', {});
  window.addEventListener('keydown', e=>{
    if(e.key === 'Escape') sendUI('escape', {});
  });

  // --- Lookups (Plate + ID) ---
  if(btnPlate) btnPlate.onclick = ()=>{
    const plate = (plateInput.value || "").trim();
    if(plate) sendUI('lookupPlate',{ plate });
  };

  if(btnId) btnId.onclick = ()=>{
    const v = (idInput.value || "").trim();
    if(!v) {
      // blank -> let client decide (will default to last stopped ped if available)
      sendUI('lookupID', {});
      return;
    }
    // if contains whitespace treat as name search ("First Last")
    if(v.indexOf(' ') !== -1) {
      sendUI('lookupID', { name: v });
    } else {
      // otherwise NetID
      sendUI('lookupID', { netId: v });
    }
  };

  // --- History selects handlers ---
  if(plateHistorySel) plateHistorySel.onchange = ()=>{
    const v = plateHistorySel.value;
    if(v) { plateInput.value = v; sendUI('lookupPlate', { plate: v }); }
  };

  if(idHistorySel) idHistorySel.onchange = ()=>{
    const v = idHistorySel.value;
    if(!v) return;
    idInput.value = v;
    if(v.indexOf(' ') !== -1) sendUI('lookupID', { name: v });
    else sendUI('lookupID', { netId: v });
  };

  // --- Helpers to render record blocks ---
  function createRecordRow(date, incidentOrType) {
    const rec = document.createElement('div');
    rec.className = 'record';
    rec.innerHTML = `
      <div class="record-field">
        <div class="record-label">DATE/TIME</div>
        <div class="record-value">${date||''}</div>
      </div>
      <div class="record-field">
        <div class="record-label">TYPE/INFO</div>
        <div class="record-value">${incidentOrType||''}</div>
      </div>
    `;
    return rec;
  }

  // --- NUI messages (from client.lua) ---
  window.addEventListener('message', evt=>{
    const d = evt.data;
    if(!d) return;

    // open/close app
    if(d.action === 'open' && app) app.classList.add('open');
    if(d.action === 'close' && app) app.classList.remove('open');

    // populate initial fields and histories
    if(d.action === 'populate') {
      if(d.plate != null) plateInput.value = d.plate;

      // prefer lastPedName if available, otherwise netId if present
      if(d.lastPedName && d.lastPedName !== "") {
        idInput.value = d.lastPedName;
      } else if(d.netId != null && d.netId !== "") {
        idInput.value = d.netId;
      } else {
        idInput.value = "";
      }

      // plateHistory array (strings)
      if(Array.isArray(d.plateHistory) && plateHistorySel) {
        plateHistorySel.innerHTML = '<option value="">-- Select previous search --</option>';
        d.plateHistory.forEach(p=>{
          const o = document.createElement('option'); o.value = p; o.textContent = p;
          plateHistorySel.appendChild(o);
        });
      }

      // idHistory array (display names or netIds)
      if(Array.isArray(d.idHistory) && idHistorySel) {
        idHistorySel.innerHTML = '<option value="">-- Select previous search --</option>';
        d.idHistory.forEach(i=>{
          const o = document.createElement('option'); o.value = i; o.textContent = i;
          idHistorySel.appendChild(o);
        });
      }
    }

    // plate result rendering
    if(d.action === 'plateResult' && plateStatus && plateIndicator) {
      plateStatus.innerHTML = '';
      const st = (d.status || '').toLowerCase();
      plateIndicator.textContent = d.status || '';
      plateIndicator.className = 'status ' + st;

      const grid = document.createElement('div');
      grid.className = 'record-grid header';
      grid.innerHTML = `
        <div>PLATE</div><div>${d.plate || ''}</div>
        <div>MAKE/MODEL</div><div>${d.make || ''}</div>
        <div>COLOR</div><div>${d.color || ''}</div>
        <div>OWNER</div><div>${d.owner || ''}</div>
        <div>INSURANCE</div><div>${d.insurance || ''}</div>
      `;
      plateStatus.appendChild(grid);

      (Array.isArray(d.records) ? d.records : []).forEach(r=>{
        const rec = document.createElement('div'); rec.className = 'record';
        const who = (((r.first_name || '') + (r.last_name ? ' ' + r.last_name : '')).trim()) || r.identifier || '';
        rec.innerHTML = `
          <div class="record-field">
            <div class="record-label">DATE/TIME</div>
            <div class="record-value">${r.timestamp || ''}</div>
          </div>
          <div class="record-field">
            <div class="record-label">INCIDENT</div>
            <div class="record-value">${who || r.identifier || ''}</div>
          </div>
        `;
        plateStatus.appendChild(rec);
      });

      if(!Array.isArray(d.records) || d.records.length === 0) {
        const nr = document.createElement('div');
        nr.className = 'no-results';
        nr.textContent = 'No history records for this plate.';
        plateStatus.appendChild(nr);
      }
    }

    // idResult rendering (for NetID or Name search)
    if(d.action === 'idResult' && idResults && idIndicator) {
      idResults.innerHTML = '';
      const ls = (d.licenseStatus || '').toLowerCase();
      idIndicator.textContent = d.licenseStatus || '';
      idIndicator.className = 'status ' + ls;

      const info = document.createElement('div');
      info.className = 'record-grid header';
      info.innerHTML = `
        <div>NET ID</div><div>${d.netId || ''}</div>
        <div>NAME</div><div>${d.name || ''}</div>
        <div>DOB</div><div>${d.dob || ''}</div>
        <div>LICENSE</div><div>${d.licenseStatus || ''}</div>
      `;
      idResults.appendChild(info);

      const records = Array.isArray(d.records) ? d.records : [];
      if(records.length === 0) {
        const nr = document.createElement('div');
        nr.className = 'no-results';
        nr.textContent = 'No ID history found.';
        idResults.appendChild(nr);
      } else {
        records.forEach(r=>{
          const rec = document.createElement('div'); rec.className = 'record';
          // show friendly name if columns exist
          const who = (((r.first_name||'') + (r.last_name ? ' ' + r.last_name : '')).trim()) || r.identifier || r.netId || '';
          rec.innerHTML = `
            <div class="record-field">
              <div class="record-label">DATE/TIME</div>
              <div class="record-value">${r.timestamp || ''}</div>
            </div>
            <div class="record-field">
              <div class="record-label">TYPE</div>
              <div class="record-value">${r.type || who || ''}</div>
            </div>
          `;
          idResults.appendChild(rec);
        });
      }

      // update idHistory select with names/identifiers for quick re-search
      if(Array.isArray(d.records) && idHistorySel) {
        const unique = [];
        idHistorySel.innerHTML = '<option value="">-- Select previous search --</option>';
        d.records.forEach(r=>{
          const display = (((r.first_name||'') + (r.last_name ? ' ' + r.last_name : '')).trim()) || r.netId || r.identifier || '';
          if(display && !unique.includes(display)) unique.push(display);
        });
        unique.forEach(u=>{
          const o = document.createElement('option'); o.value = u; o.textContent = u;
          idHistorySel.appendChild(o);
        });
      }
    }
  });

  // Expose sendUI for dev console if needed
  window._ncic_sendUI = sendUI;
})();