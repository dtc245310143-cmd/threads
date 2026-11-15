(function (global) {
  'use strict';
  function extract(documents, code) {
    const posts = new Map(), groups = [], ignored = new Set(['relatedPosts', 'related_posts', 'suggested_posts', 'quoted_post', 'quoted_attachment_post', 'reposted_post']);
    let visited = 0;
    const number = x => Number.isInteger(x) && x >= 0 ? x : 0;
    function record(node) {
      const info = node.text_post_app_info || {}, user = node.user || {};
      const fragment = ((info.text_fragments || {}).fragments || []).map(x => x.plaintext || '').join('');
      const caption = (node.caption || {}).text || '';
      const photos = (node.carousel_media || [node]).filter(x => x && x.media_type !== 2).map(x => {
        const candidates = ((x.image_versions2 || {}).candidates || []).filter(c => typeof c.url === 'string');
        candidates.sort((a,b) => number(b.width)*number(b.height)-number(a.width)*number(a.height));
        return candidates[0]?.url;
      }).filter(Boolean);
      return {id:String(node.pk || node.id || node.code).split('_')[0], code:node.code, author:user.username || '',
        text:(fragment.length > caption.length ? fragment : caption).trim(), likes:number(node.like_count), replies:number(info.direct_reply_count),
        authorLiked:info.is_liked_by_root_author === true, authorReplied:false, isReply:info.is_reply === true,
        rootAuthor:(info.root_post_author || {}).username || '', replyToAuthor:(info.reply_to_author || {}).username || '', images:[...new Set(photos)].slice(0,20)};
    }
    function walk(node) {
      if (++visited > 150000 || !node || typeof node !== 'object') return;
      if (Array.isArray(node)) { node.forEach(walk); return; }
      if (node.code && node.user && typeof node.user.username === 'string') {
        const current = record(node), previous = posts.get(current.id);
        if (previous) {
          if (previous.text.length > current.text.length) current.text = previous.text;
          if (previous.images.length > current.images.length) current.images = previous.images;
          current.authorLiked ||= previous.authorLiked;
        }
        posts.set(current.id,current);
      }
      if (Array.isArray(node.thread_items)) groups.push(node.thread_items.map(x => x.post).filter(Boolean));
      if (Array.isArray(node.posts?.edges)) groups.push(node.posts.edges.map(x => x.node).filter(Boolean));
      Object.keys(node).filter(key => !ignored.has(key)).forEach(key => walk(node[key]));
    }
    documents.forEach(walk);
    const root = [...posts.values()].find(x => x.code === code && !x.isReply) || [...posts.values()].find(x => x.code === code);
    if (!root) return null;
    for (const group of groups) {
      const chain = group.filter(x => x.code && x.user).map(record), first = chain[0];
      if (!first?.isReply || first.rootAuthor !== root.author) continue;
      if (chain.slice(1).some(x => x.author === root.author && x.replyToAuthor === first.author)) {
        const original = posts.get(first.id); if (original) original.authorReplied = true;
      }
    }
    return {root, comments:[...posts.values()].filter(x => x.id !== root.id && x.isReply && x.rootAuthor === root.author && x.text).slice(0,500)};
  }
  if (typeof module !== 'undefined') { module.exports = {extract}; return; }
  if (!['threads.com','www.threads.com','threads.net','www.threads.net'].includes(location.hostname)) return;
  const documents = []; let total = 0; const scripts = new WeakSet();
  function collect(raw) {
    if (typeof raw !== 'string' || raw.length > 8000000 || total + raw.length > 24000000) return;
    try { const data = JSON.parse(raw.replace(/^for\s*\(;;\);/,'')); documents.push(data);total += raw.length; } catch (_) {}
  }
  const originalFetch = window.fetch;
  window.fetch = async function (...args) {
    const response = await originalFetch.apply(this,args);
    try {
      const url = new URL(response.url);
      if (url.origin === location.origin && url.pathname.includes('graphql')) response.clone().text().then(collect).catch(() => {});
    } catch (_) {}
    return response;
  };
  const originalOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (...args) {
    this.addEventListener('load',function () {
      try { const url = new URL(this.responseURL); if (url.origin === location.origin && url.pathname.includes('graphql') && this.responseType !== 'json') collect(this.responseText); } catch (_) {}
    });
    return originalOpen.apply(this,args);
  };
  function expand() {
    const names = /^(?:Xem thêm|Đọc thêm|See more|Read more|(?:View|See|Show|Xem|Hiển thị)\s+(?:\d+\s+)?(?:more\s+)?(?:repl(?:y|ies)|phản hồi|câu trả lời|trả lời))$/i;
    [...document.querySelectorAll('button,[role="button"]')].filter(x => x.getBoundingClientRect().height && names.test(x.innerText.trim())).slice(0,8).forEach(x => x.click());
  }
  function result() {
    document.querySelectorAll('script[type="application/json"]').forEach(script => { if (!scripts.has(script)) { scripts.add(script);collect(script.textContent); } });
    const code = location.pathname.match(/\/post\/([\w-]+)/)?.[1];
    return code ? extract(documents,code) : null;
  }
  function cleanup() { document.getElementById('threads-studio-capture')?.remove(); }
  function prepare(post, chunk) {
    cleanup(); const norm = x => (x || '').replace(/[\u200b-\u200d\ufeff]/g,'').replace(/\s+/g,' ').trim();
    const source = norm(post.text), prefix = source.slice(0,32);
    let card, content;
    for (const link of [...document.querySelectorAll('a[href]')].filter(a => { try { return new URL(a.href).pathname.replace(/\/$/,'').endsWith('/post/'+post.code); } catch (_) { return false; } })) {
      for (let parent = link.parentElement, depth = 0; parent && depth < 14; parent = parent.parentElement, depth++) {
        const box = parent.getBoundingClientRect(); if (box.width < 200 || box.width > 950 || box.height < 45) continue;
        const codes = new Set([...parent.querySelectorAll('a[href]')].map(a => { try {return new URL(a.href).pathname.match(/\/post\/([^/]+)/)?.[1];} catch (_) {return null;} }).filter(Boolean));
        if (codes.size > 1) break;
        const candidate = [...parent.querySelectorAll('[dir="auto"],span,div')].filter(x => norm(x.textContent).startsWith(prefix) && !x.querySelector('svg,time') && norm(x.textContent).length <= Math.max(source.length+100,400));
        const chosen = candidate.filter(x => norm(x.textContent) === source).at(-1) || candidate.sort((a,b) => norm(b.textContent).length-norm(a.textContent).length)[0];
        if (prefix && chosen) { card = parent;content = chosen;break; }
      }
      if (card) break;
    }
    if (!card || !content) return null;
    const clone = card.cloneNode(true), originals = [card,...card.querySelectorAll('*')], copies = [clone,...clone.querySelectorAll('*')], target = copies[originals.indexOf(content)];
    originals.forEach((x,i) => { const style = getComputedStyle(x);copies[i].style.cssText = Array.from(style).map(k => k+':'+style.getPropertyValue(k)).join(';'); });
    target.textContent = chunk;
    for (let element = target; element; element = element.parentElement) {
      Object.assign(element.style,{height:'auto',maxHeight:'none',overflow:'visible',webkitLineClamp:'unset'});
      if (element === clone) break;
    }
    Object.assign(target.style,{display:'block',whiteSpace:'pre-wrap'});
    const mount = document.createElement('div');mount.id = 'threads-studio-capture';
    Object.assign(mount.style,{position:'fixed',left:'8px',top:'8px',zIndex:'2147483647',background:getComputedStyle(document.body).backgroundColor,padding:'0',width:Math.min(card.getBoundingClientRect().width,innerWidth-16)+'px'});
    Object.assign(clone.style,{width:'100%',position:'relative',inset:'auto',margin:'0'});
    mount.appendChild(clone);document.body.appendChild(mount);
    const box = mount.getBoundingClientRect();
    return {x:box.x,y:box.y,width:box.width,height:Math.min(box.height,innerHeight-16)};
  }
  global.ThreadsStudio = {expand,result,prepare,cleanup};
})(globalThis);
