
PROVE := perl extlib/bin/prove

JOBS:=4

OPTIMIZE_FLAGS := lto,no-assert,fold-const,return-if,inline,dce,unbox,fold-const,lcse,dce,fold-const,array-length,unclassify

all: compiler doc web

## compiler stuff

compiler: src/doc.jsx meta
	node tool/bootstrap-compiler.js --executable node --output bin/jsx src/jsx-node-front.jsx

src/doc.jsx: src/_doc.jsx
	submodules/picotemplate/picotemplate.pl $<

meta:
	if [ -e .git ] ; then tool/make-meta package.json src/meta.jsx ; fi

doc: src/doc.jsx
	rm -rf doc
	find lib -name '*.jsx' | xargs -n 1 -- bin/jsx --mode doc --output doc

self-hosting-compiler: compiler
	bin/jsx --disable-type-check --executable node --output bin/jsx src/jsx-node-front.jsx # again
	cp bin/jsx tool/bootstrap-compiler.js

## test stuff

# e.g. make test JOBS=2

test: test-debug test-optimized

test-debug: compiler
	$(PROVE) --jobs "$(JOBS)" t/*.t t/*/*.jsx

test-optimized: compiler
	JSX_OPTS="--optimize $(OPTIMIZE_FLAGS)" $(PROVE) --jobs "$(JOBS)" t/*/*.jsx


optimize-bench:
	$(PROVE) -v xt/optimize-bench/*.jsx

## web stuff

web: compiler
	perl web/build.pl

server: web
	node web/server.js

# for authors
web.jsx:
	idl2jsx/build.pl
	idl2jsx/maketest.pl > t/lib/010.web.jsx
	bin/jsx --test t/lib/010.web.jsx


show-todo:
	find t -name '*.todo.*' | grep -v '*~'

update-assets: update-bootstrap update-codemirror

update-codemirror:
	rm -rf codemirror*
	curl -LO http://codemirror.net/codemirror.zip
	unzip -o codemirror.zip
	cp codemirror-*/lib/codemirror.css            web/assets/css
	cp codemirror-*/lib/codemirror.js             web/assets/js
	cp codemirror-*/addon/hint/simple-hint.css    web/assets/css
	cp codemirror-*/addon/hint/simple-hint.js     web/assets/js
	cp codemirror-*/mode/javascript/javascript.js web/assets/js/mode
	cp codemirror-*/mode/clike/clike.js           web/assets/js/mode

update-bootstrap:
	curl -LO http://twitter.github.com/bootstrap/assets/bootstrap.zip
	unzip -o bootstrap.zip
	cp bootstrap/css/*.* web/assets/css
	cp bootstrap/img/*.* web/assets/img
	cp bootstrap/js/*.*  web/assets/js

## cleanup

clean:
	rm -rf CodeMirror-* codemirror.zip
	rm -rf bootstrap*
	rm -rf bin/*
	rm -rf jsx-*.tgz

.PHONY: setup test web server doc meta
