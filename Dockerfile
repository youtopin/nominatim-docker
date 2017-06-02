# -*-dockerfile-*-

FROM ubuntu:16.04
MAINTAINER Natan Sągol <m@merlinnot.com>

# Update image
RUN apt-get -qq update && apt-get -qq upgrade -y -o \
      Dpkg::Options::="--force-confold"

# Update locales
RUN apt-get install -y --no-install-recommends locales
ENV DEBIAN_FRONTEND noninteractive
ENV LANG C.UTF-8
RUN locale-gen en_US.UTF-8
RUN update-locale LANG=en_US.UTF-8

# Add sources
RUN apt-get install -y --no-install-recommends wget
RUN echo "deb http://apt.postgresql.org/pub/repos/apt xenial-pgdg main" >> \
      /etc/apt/sources.list && \
    wget --quiet -O - http://apt.postgresql.org/pub/repos/apt/ACCC4CF8.asc | \
      apt-key add -
RUN apt-get -qq update

# Install build dependencies
RUN apt-get install -y --no-install-recommends \
      apache2 \
      build-essential \
      ca-certificates \
      cmake \
      curl \
      g++ \
      git \
      libapache2-mod-php \
      libboost-dev \
      libboost-filesystem-dev \
      libboost-python-dev \
      libboost-system-dev \
      libbz2-dev \
      libexpat1-dev \
      libgeos-dev \
      libgeos++-dev \
      libpq-dev \
      libproj-dev \
      libxml2-dev\
      openssl \
      osmosis \
      php \
      php-db \
      php-pear \
      php-pgsql \
      postgresql-9.5-postgis-2.2 \
      postgresql-9.5-postgis-scripts \
      postgresql-contrib-9.5 \
      postgresql-server-dev-9.5 \
      python \
      python-pip \
      python-setuptools \
      sudo \
      zlib1g-dev
RUN pip install --upgrade pip
RUN pip install osmium

RUN useradd -d /srv/nominatim -s /bin/bash -m nominatim
ENV USERNAME nominatim
ENV USERHOME /srv/nominatim
RUN chmod a+x ${USERHOME}

# Install Nominatim
USER nominatim
WORKDIR /srv/nominatim
RUN git clone --recursive git://github.com/openstreetmap/Nominatim.git
RUN wget -O Nominatim/data/country_osm_grid.sql.gz \
      http://www.nominatim.org/data/country_grid.sql.gz
RUN mkdir ${USERHOME}/Nominatim/build && \
    cd ${USERHOME}/Nominatim/build && \
    cmake ${USERHOME}/Nominatim && \
    make

# Download data for initial import
USER nominatim
ENV PBF_DATA http://download.geofabrik.de/europe-latest.osm.pbf
RUN curl -L $PBF_DATA --create-dirs -o /srv/nominatim/src/data.osm.pbf

# Tune postgresql configuration
COPY postgresql-import.conf /etc/postgresql/9.5/main/postgresql.conf

# Add postgresql users
USER root
RUN service postgresql start && \
    sudo -u postgres createuser -s nominatim && \
    sudo -u postgres createuser www-data && \
    service postgresql stop

# Initial import
USER root
ENV IMPORT_THREADS 31
RUN service postgresql start && \
    sudo -u nominatim ${USERHOME}/Nominatim/build/utils/setup.php \
      --osm-file /srv/nominatim/src/data.osm.pbf \
      --all \
      --threads $IMPORT_THREADS \
      --osm2pgsql-cache 28000 && \
    service postgresql stop

# Use safe postgresql configuration
COPY postgresql-safe.conf /etc/postgresql/9.5/main/postgresql.conf

# Configure Apache
COPY nominatim.conf /etc/apache2/conf-available/nominatim.conf
RUN a2enconf nominatim

# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Expose ports
EXPOSE 8080

# Init script
COPY start.sh /srv/nominatim/start.sh
CMD ["/srv/nominatim/start.sh"]
