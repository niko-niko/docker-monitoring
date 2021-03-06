FROM     ubuntu:14.04

# ---------------- #
#   Installation   #
# ---------------- #

ENV DEBIAN_FRONTEND noninteractive

# Install all prerequisites
RUN     apt-get -y update
RUN     apt-get -y install software-properties-common
RUN     add-apt-repository -y ppa:chris-lea/node.js
RUN     apt-get -y update
RUN     apt-get -y install python-django-tagging python-simplejson python-memcache \
            python-ldap python-cairo python-pysqlite2 python-support \
            python-pip gunicorn supervisor nginx-light nodejs git wget curl \
            openjdk-7-jre build-essential python-dev build-essential \
            libcurl4-gnutls-dev libmysqlclient-dev libhiredis-dev liboping-dev \
            libyajl-dev libpq-dev

RUN     pip install Twisted==11.1.0
RUN     pip install Django==1.5
RUN     pip install pytz
RUN     npm install ini chokidar

# Checkout the stable branches of Graphite, Carbon and Whisper and install from there
RUN     mkdir /src
RUN     git clone https://github.com/graphite-project/whisper.git /src/whisper            &&\
        cd /src/whisper                                                                   &&\
        git checkout 0.9.x                                                                &&\
        python setup.py install

RUN     git clone https://github.com/graphite-project/carbon.git /src/carbon              &&\
        cd /src/carbon                                                                    &&\
        git checkout 0.9.x                                                                &&\
        python setup.py install


RUN     git clone https://github.com/graphite-project/graphite-web.git /src/graphite-web  &&\
        cd /src/graphite-web                                                              &&\
        git checkout 0.9.x                                                                &&\
        python setup.py install

# Install StatsD
RUN     git clone https://github.com/etsy/statsd.git /src/statsd                          &&\ 
        cd /src/statsd                                                                    &&\
        git checkout v0.8.0 

# Install Grafana
RUN     mkdir /src/grafana                                                                &&\
        mkdir /opt/grafana                                                                &&\
        wget https://grafanarel.s3.amazonaws.com/builds/grafana-3.1.0-1468321182.linux-x64.tar.gz -O /src/grafana.tar.gz                                                                    &&\
        tar -xzf /src/grafana.tar.gz -C /opt/grafana --strip-components=1                 &&\
        rm /src/grafana.tar.gz

# Compile collectd from source in order to change the location of /proc to /host/proc,
# this assumes the container is launched with -v /proc:/host/proc
RUN curl https://collectd.org/files/collectd-5.5.0.tar.gz | tar zxf -                    &&\
    cd collectd*                                                                         &&\
    ./configure --prefix=/usr --sysconfdir=/etc/collectd --localstatedir=/var --enable-debug &&\
    grep -rl /proc/ . | xargs sed -i "s/\/proc\//\/host\/proc\//g"                       &&\
    make all install                                                                     &&\
    make clean


# ----------------- #
#   Configuration   #
# ----------------- #

# Configure Nginx
ADD     ./nginx/nginx.conf /etc/nginx/sites-enabled/default

# Confiure StatsD
ADD     ./statsd/config.js /src/statsd/config.js

# Configure Whisper, Carbon and Graphite-Web
ADD     ./graphite/initial_data.json /opt/graphite/webapp/graphite/initial_data.json
ADD     ./graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
ADD     ./graphite/carbon.conf /opt/graphite/conf/carbon.conf
ADD     ./graphite/storage-schemas.conf /opt/graphite/conf/storage-schemas.conf
ADD     ./graphite/storage-aggregation.conf /opt/graphite/conf/storage-aggregation.conf
RUN     mkdir -p /opt/graphite/storage/whisper
RUN     touch /opt/graphite/storage/graphite.db /opt/graphite/storage/index
RUN     chown -R www-data /opt/graphite/storage
RUN     chmod 0775 /opt/graphite/storage /opt/graphite/storage/whisper
RUN     chmod 0664 /opt/graphite/storage/graphite.db
RUN     cd /opt/graphite/webapp/graphite && python manage.py syncdb --noinput

# Configure Grafana
ADD     ./grafana/custom.ini /opt/grafana/conf/custom.ini
RUN     chown -R www-data:www-data /opt/graphite

# Add the default dashboards
RUN     mkdir /src/dashboards
ADD     ./grafana/dashboards/* /src/dashboards/
RUN     mkdir /src/dashboard-loader
ADD     ./grafana/dashboard-loader/dashboard-loader.js /src/dashboard-loader/

# Configure nginx and supervisord
ADD     ./nginx/nginx.conf /etc/nginx/nginx.conf
ADD     ./supervisord/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Confuration script for collectd
ADD     ./collectd/create_collectd_conf.bash /root/create_collectd_conf.bash
ADD     ./collectd/collectd.env /root/collectd.env
RUN     chmod +x /root/create_collectd_conf.bash
RUN     /root/create_collectd_conf.bash /root/collectd.env > /etc/collectd/collectd.conf
RUN     mkdir -p /host


# ---------------- #
#   Expose Ports   #
# ---------------- #

## Grafana
#EXPOSE  80
#
## StatsD UDP port
#EXPOSE  8125/udp
#
## StatsD Management port
#EXPOSE  8126
#
## Graphite web port
#EXPOSE 81



# -------- #
#   Run!   #
# -------- #

CMD     ["/usr/bin/supervisord"]
