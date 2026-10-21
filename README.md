### Installation
```
cd ~
git clone git@github.com:dorigoa/Strata.git
cd Strata
git clone https://github.com/Niko1221/Strata.git
cd Strata
./setup.sh --no-start # then answer the questions
```
Based on the selected model, a json config file is generated, e.g. `strata-unsloth-ud-q4_k_xl.json`.
```
cp strata-unsloth-ud-q4_k_xl.json ~/Strata/
cd ~/Strata
./Strata/.venv/bin/python ./Strata/serve/server.py --engine strata --config ./strata-unsloth-ud-q4_k_xl.json --port 8080 --open
```

Install the port-forwarding socat service file into systemd config directory:

```
sudo cp strata-socat.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now strata-socat.service
```
The `socat` port forwarder is needed as Strata must bind to local address `127.0.0.1` (otherwise an API key is mandatory).
So, to connect to the Strata's web server on the public IP (`192.168.1.200`) we need a `socat` proxy.
