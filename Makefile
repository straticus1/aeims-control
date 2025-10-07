.PHONY: agent.init agent.scan agent.verify aeims.build aeims.deploy aeims.test

# MCP Agent initialization
agent.init:
	mkdir -p ./.agent/logs
	@test -f ./.agent/mcp-registry.json || (mkdir -p ./.agent && printf '{\n  "servers": {}\n}\n' > ./.agent/mcp-registry.json)
	@test -f ./.env.master || printf '# AEIMS Master Environment Configuration\n' > ./.env.master

agent.scan:
	@echo "Scanning AEIMS integrated project structure..." > ./.agent/REQUEST.md
	@echo "- aeims-control: Infrastructure as Code" >> ./.agent/REQUEST.md
	@echo "- aeims: Core VoIP telephony platform" >> ./.agent/REQUEST.md
	@echo "- aeimsLib: Interactive device control library" >> ./.agent/REQUEST.md
	@cat ./.agent/REQUEST.md

agent.verify:
	@echo "Verifying AEIMS integration health..." > ./.agent/VERIFY.md
	@echo "Checking terraform, docker, and service connectivity" >> ./.agent/VERIFY.md
	@cat ./.agent/VERIFY.md

# AEIMS specific operations
aeims.build:
	@echo "Building all AEIMS components..."
	docker-compose build --parallel

aeims.deploy:
	@echo "Deploying unified AEIMS infrastructure..."
	./deploy-unified.sh

aeims.test:
	@echo "Testing AEIMS integration..."
	./test-integration.sh