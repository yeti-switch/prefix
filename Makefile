PKGNAME = prefix
PKGVERS = $(shell dpkg-parsechangelog | awk -F '[:-]' '/^Version:/ { print substr($$2, 2) }')
EXTVERS = $(shell awk -F "[= ']" '/default_version/ {print $$5}' prefix.control)

EXTENSION = prefix
MODULES = prefix
DATA = prefix--1.2.0.sql prefix--unpackaged--1.2.0.sql prefix--1.1--1.2.0.sql
DOCS = $(wildcard *.md)
# use extenstion in 9.1+
SETUPSQL = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo create_module || echo create_extension)
# "explain (costs off)" needs 9.0+ (and 9.0 needs expected/explain_1.out)
EXPLAINSQL = $(shell $(PG_CONFIG) --version | grep -qE " 8\." || echo explain)
REGRESS = $(SETUPSQL) prefix falcon $(EXPLAINSQL) queries

# support for 8.1 which didn't expose PG_VERSION_NUM -- another trick from ip4r
PREFIX_PGVER = $(shell echo $(VERSION) | awk -F. '{ print $$1*100+$$2 }')
PG_CPPFLAGS  = -DPREFIX_PGVER=$(PREFIX_PGVER)

PG_CONFIG ?= pg_config
PGXS = $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

deb: clean
	make -f debian/rules debian/control
	dh clean
	make -f debian/rules orig
	debuild -us -uc -sa
