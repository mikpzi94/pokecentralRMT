(function(){
  var payload='00020126580014BR.GOV.BCB.PIX013686651e0f-f453-4972-bfc8-eb9ae3cdc8df5204000053039865802BR5925Mikael Rodrigues Pelizari6009SAO PAULO621405107Pki2FBuIm63042423';
  document.querySelectorAll('.apoio-pix-btn').forEach(function(btn){
    btn.addEventListener('click',function(){
      var panel=this.closest('.apoio').querySelector('.pix-panel');
      panel.classList.toggle('open');
      this.setAttribute('aria-expanded',panel.classList.contains('open')?'true':'false');
    });
  });
  document.querySelectorAll('.pix-copy').forEach(function(btn){
    btn.addEventListener('click',function(){
      var status=this.parentNode.querySelector('.pix-status');
      function ok(){status.textContent='✓ Código Pix copiado';status.style.color='var(--green)';}
      function fallback(){
        var t=document.createElement('textarea');t.value=payload;t.style.position='fixed';t.style.opacity='0';document.body.appendChild(t);t.select();
        try{document.execCommand('copy');ok();}catch(e){status.textContent='Não foi possível copiar. Use o QR Code.';status.style.color='var(--red)';}
        document.body.removeChild(t);
      }
      if(navigator.clipboard&&navigator.clipboard.writeText)navigator.clipboard.writeText(payload).then(ok).catch(fallback);else fallback();
    });
  });
})();
