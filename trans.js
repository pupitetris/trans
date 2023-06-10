const readline = require('readline');
const fs = require('fs');


const INPUT_SOURCE = process.argv[2];

var TRANS_FUNC_NAME = '';
trans_src = (function () {
    /* This is horrible, but otherwise it's C-style file reading: */
    const src = fs.readFileSync(INPUT_SOURCE, 'utf-8');
    const lines = src.split('\n');

    let trans_found = false;
    let trans_src = '';
    const decl_re = new RegExp('^var +([^ =]+) *= *function *\\(');
    let i = 0;
    for (const line of lines) {
	match = line.match(decl_re);
	if (match) {
	    if (trans_found)
		return trans_src;
	    TRANS_FUNC_NAME = match[1];
	    trans_found = true;
	}
	trans_src += line;
    }
})();
eval(trans_src);

const TRANS_FUNC = eval(TRANS_FUNC_NAME);
function trans(a, b) {
    var c = TRANS_FUNC(a, b);

    b = b.replace(/\[/g, "\\[");
    b = b.replace(/\]/g, "\\]");
    b = b.replace(/\*/g, "\\*");

    c = c.replace(/\&/g, "\\&");
    c = c.replace(/\//g, "\\/");
    c = c.replace(/\'/g, "\\\\'");
    c = c.replace(/\n/g, "\\\\n");

    return `s/${TRANS_FUNC_NAME}('${a}', \\?'${b}')/'${c}'/g`;
}

const inter = readline.createInterface({
    input: process.stdin,
    terminal: false
});

inter.on('line', (line) => {
    const [a, b] = line.split("\t");
    console.log(trans(a, b));
});
