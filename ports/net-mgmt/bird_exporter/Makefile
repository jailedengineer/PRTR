PORTNAME=	bird_exporter
DISTVERSIONPREFIX=	v
DISTVERSION=	1.4.5
CATEGORIES=	net-mgmt

MAINTAINER=	paulo@nlink.com.br
COMMENT=	Prometheus exporter for BIRD routing daemon metrics
WWW=		https://github.com/czerwonk/bird_exporter

LICENSE=	MIT
LICENSE_FILE=	${WRKSRC}/LICENSE

USES=		go:modules
USE_RC_SUBR=	bird_exporter

GO_MODULE=	github.com/czerwonk/bird_exporter
GO_BUILDFLAGS=	-v -ldflags "-s -w"

OPTIONS_DEFINE=	DOCS

post-install-DOCS-on:
	${MKDIR} ${STAGEDIR}${DOCSDIR}
	${INSTALL_DATA} ${WRKSRC}/README.md ${STAGEDIR}${DOCSDIR}

.include <bsd.port.mk>
