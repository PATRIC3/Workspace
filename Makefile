TOP_DIR = ../..
include $(TOP_DIR)/tools/Makefile.common

TARGET ?= /kb/deployment
DEPLOY_TARGET ?= $(TARGET)
DEPLOY_RUNTIME ?= /kb/runtime
SERVER_SPEC = Workspace.spec

SERVICE_MODULE = lib/Bio/P3/Workspace/Service.pm

SERVICE = Workspace
SERVICE_PORT = 7125
DOWNLOAD_SERVICE = WorkspaceDownload
DOWNLOAD_SERVICE_PORT = 7129
COMPLETION_SERVICE = WorkspaceCompletion
COMPLETION_SERVICE_PORT = 7140

SERVICE_URL = https://p3.theseed.org/services/$(SERVICE)
DOWNLOAD_URL = https://p3.theseed.org/services/$(DOWNLOAD_SERVICE)
COMPLETION_URL = https://p3.theseed.org/services/$(COMPLETION_SERVICE)

SERVICE_NAME = Workspace
SERVICE_NAME_PY = $(SERVICE_NAME)
DOWNLOAD_SERVICE_NAME = WorkspaceDownload
COMPLETION_SERVICE_NAME = WorkspaceCompletion

SERVICE_PSGI_FILE = $(SERVICE_NAME).psgi
DOWNLOAD_SERVICE_PSGI_FILE = $(DOWNLOAD_SERVICE_NAME).psgi
COMPLETION_SERVICE_PSGI_FILE = $(COMPLETION_SERVICE_NAME).psgi

SRC_SERVICE_PERL = $(wildcard service-scripts/*.pl) $(wildcard internal-scripts/*.pl)
BIN_SERVICE_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_SERVICE_PERL))))
DEPLOY_SERVICE_PERL = $(addprefix $(SERVICE_DIR)/bin/,$(basename $(notdir $(SRC_SERVICE_PERL))))

ifdef TEMPDIR
TPAGE_TEMPDIR = --define kb_tempdir=$(TEMPDIR)
endif

ifdef DEPLOYMENT_VAR_DIR
SERVICE_LOGDIR = $(DEPLOYMENT_VAR_DIR)/services/$(SERVICE)
TPAGE_SERVICE_LOGDIR = --define kb_service_log_dir=$(SERVICE_LOGDIR)
endif

TPAGE_DEPLOY_ARGS = \
	--define kb_top=$(DEPLOY_TARGET) \
	--define kb_runtime=$(DEPLOY_RUNTIME) 

TPAGE_BUILD_ARGS = \
	--define kb_top=$(TARGET) \
	--define kb_runtime=$(DEPLOY_RUNTIME) 

TPAGE_ARGS =  \
	--define kb_service_name=$(SERVICE) \
	--define kb_service_port=$(SERVICE_PORT) \
	--define kb_psgi=$(SERVICE_PSGI_FILE) \
	--define kb_download_port=$(DOWNLOAD_SERVICE_PORT) \
	--define kb_download_psgi=$(DOWNLOAD_SERVICE_PSGI_FILE) \
	--define kb_completion_port=$(COMPLETION_SERVICE_PORT) \
	--define kb_completion_psgi=$(COMPLETION_SERVICE_PSGI_FILE) \
	--define kb_starman_workers=25 \
	$(TPAGE_TEMPDIR) \
	$(TPAGE_SERVICE_LOGDIR)

TESTS = $(wildcard t/client-tests/*.t)

all: bin compile-typespec service

jarfile:
	gen_java_client $(SERVER_SPEC) org.patricbrc.Workspace java
	javac java/org/patricbrc/Workspace/*java
	cd java; jar cf ../Workspace.jar org/patricbrc/Workspace/*.class

test:
	# run each test
	echo "RUNTIME=$(DEPLOY_RUNTIME)\n"
	for t in $(TESTS) ; do \
		if [ -f $$t ] ; then \
			$(DEPLOY_RUNTIME)/bin/perl $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

service: $(SERVICE_MODULE)

compile-typespec: Makefile
	mkdir -p lib/biop3/$(SERVICE_NAME_PY)
	touch lib/biop3/__init__.py #do not include code in biop3/__init__.py
	touch lib/biop3/$(SERVICE_NAME_PY)/__init__.py 
	mkdir -p lib/javascript/$(SERVICE_NAME)
	compile_typespec \
		--patric \
		--psgi $(SERVICE_PSGI_FILE) \
		--impl Bio::P3::$(SERVICE_NAME)::$(SERVICE_NAME)Impl \
		--service Bio::P3::$(SERVICE_NAME)::Service \
		--client Bio::P3::$(SERVICE_NAME)::$(SERVICE_NAME)Client \
		--py biop3/$(SERVICE_NAME_PY)/$(SERVICE_NAME)Client \
		--js javascript/$(SERVICE_NAME)/$(SERVICE_NAME)Client \
		--url $(SERVICE_URL) \
		$(SERVER_SPEC) lib
	-rm -f lib/$(SERVER_MODULE)Server.py
	-rm -f lib/$(SERVER_MODULE)Impl.py

bin: $(BIN_PERL) $(BIN_SERVICE_PERL)

deploy: deploy-client deploy-service
deploy-all: deploy-client deploy-service
deploy-client: compile-typespec deploy-docs deploy-libs deploy-scripts 

deploy-service: deploy-dir deploy-monit deploy-libs deploy-service-scripts-local
	$(TPAGE) $(TPAGE_DEPLOY_ARGS) $(TPAGE_ARGS) service/start_service.tt > $(TARGET)/services/$(SERVICE)/start_service
	chmod +x $(TARGET)/services/$(SERVICE)/start_service
	$(TPAGE) $(TPAGE_DEPLOY_ARGS) $(TPAGE_ARGS) service/stop_service.tt > $(TARGET)/services/$(SERVICE)/stop_service
	chmod +x $(TARGET)/services/$(SERVICE)/stop_service

deploy-service-scripts-local:
	export KB_TOP=$(DEPLOY_TARGET); \
	export KB_RUNTIME=$(DEPLOY_RUNTIME); \
	export KB_PERL_PATH=$(TARGET)/lib ; \
	export PATH_PREFIX=$(DEPLOY_TARGET)/services/$(SERVICE)/bin:$(DEPLOY_TARGET)/services/cdmi_api/bin; \
	for src in $(SRC_SERVICE_PERL) ; do \
	        basefile=`basename $$src`; \
	        base=`basename $$src .pl`; \
	        echo install $$src $$base ; \
	        cp $$src $(TARGET)/plbin ; \
	        $(WRAP_PERL_SCRIPT) "$(TARGET)/plbin/$$basefile" $(TARGET)/services/$(SERVICE)/bin/$$base ; \
	done

deploy-monit:
	$(TPAGE) $(TPAGE_DEPLOY_ARGS) $(TPAGE_ARGS) service/process.$(SERVICE).tt > $(TARGET)/services/$(SERVICE)/process.$(SERVICE)

deploy-docs:
	-mkdir doc
	-mkdir $(SERVICE_DIR)
	-mkdir $(SERVICE_DIR)/webroot
	mkdir -p doc
	$(DEPLOY_RUNTIME)/bin/pod2html -t "Workspace API" lib/Bio/P3/Workspace/WorkspaceImpl.pm > doc/workspace_impl.html
	cp doc/*html $(SERVICE_DIR)/webroot/.

deploy-dir:
	if [ ! -d $(SERVICE_DIR) ] ; then mkdir $(SERVICE_DIR) ; fi
	if [ ! -d $(SERVICE_DIR)/webroot ] ; then mkdir $(SERVICE_DIR)/webroot ; fi
	if [ ! -d $(SERVICE_DIR)/bin ] ; then mkdir $(SERVICE_DIR)/bin ; fi

$(BIN_DIR)/%: internal-scripts/%.pl $(TOP_DIR)/user-env.sh
	$(WRAP_PERL_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

include $(TOP_DIR)/tools/Makefile.common.rules
