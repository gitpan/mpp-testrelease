function lr(cur) {
  cur.parentNode.parentNode.className = (cur.parentNode.parentNode.className=='left') ? 'right' : 'left';
}

function nonav(cur) {
  cur.parentNode.parentNode.className = 'none';
}

function fold(cur) {
  cur.className = (cur.className=='fold') ? 'unfold' : 'fold';
}