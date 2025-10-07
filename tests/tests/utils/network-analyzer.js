const fs = require('fs-extra');
const { spawn } = require('child_process');
const path = require('path');

class NetworkAnalyzer {
  constructor() {
    this.captureFile = path.join(__dirname, '..', 'test-results', 'network-capture.pcap');
    this.tsharkProcess = null;
    this.analysisResults = [];
  }

  async startCapture() {
    await fs.ensureDir(path.dirname(this.captureFile));
    
    return new Promise((resolve, reject) => {
      // Start tshark capture
      this.tsharkProcess = spawn('tshark', [
        '-i', 'any',
        '-w', this.captureFile,
        '-f', 'tcp port 80 or tcp port 443'
      ]);

      this.tsharkProcess.on('error', (error) => {
        console.warn('tshark not available, skipping network capture:', error.message);
        resolve(); // Continue without network capture
      });

      setTimeout(() => {
        console.log('Network capture started');
        resolve();
      }, 1000);
    });
  }

  async stopCapture() {
    if (this.tsharkProcess) {
      this.tsharkProcess.kill('SIGTERM');
      this.tsharkProcess = null;
      console.log('Network capture stopped');
    }
  }

  async analyzeTraffic() {
    if (!await fs.pathExists(this.captureFile)) {
      console.log('No capture file found, skipping traffic analysis');
      return [];
    }

    return new Promise((resolve) => {
      const analysis = spawn('tshark', [
        '-r', this.captureFile,
        '-T', 'json',
        '-e', 'frame.time',
        '-e', 'ip.src',
        '-e', 'ip.dst',
        '-e', 'tcp.dstport',
        '-e', 'http.request.method',
        '-e', 'http.request.uri',
        '-e', 'http.response.code'
      ]);

      let output = '';
      analysis.stdout.on('data', (data) => {
        output += data.toString();
      });

      analysis.on('close', () => {
        try {
          const packets = JSON.parse(output);
          resolve(this.processPackets(packets));
        } catch (error) {
          console.warn('Failed to parse network analysis:', error.message);
          resolve([]);
        }
      });

      analysis.on('error', () => {
        console.warn('tshark analysis failed, continuing without network analysis');
        resolve([]);
      });
    });
  }

  processPackets(packets) {
    const results = [];
    
    for (const packet of packets) {
      if (packet._source?.layers) {
        const layers = packet._source.layers;
        results.push({
          timestamp: layers['frame.time']?.[0],
          source: layers['ip.src']?.[0],
          destination: layers['ip.dst']?.[0],
          port: layers['tcp.dstport']?.[0],
          method: layers['http.request.method']?.[0],
          uri: layers['http.request.uri']?.[0],
          responseCode: layers['http.response.code']?.[0]
        });
      }
    }

    return results;
  }

  generateNetworkReport(packets) {
    const report = {
      totalPackets: packets.length,
      httpRequests: packets.filter(p => p.method).length,
      responsesByCode: {},
      uniqueHosts: new Set(),
      requestsByMethod: {}
    };

    for (const packet of packets) {
      if (packet.responseCode) {
        report.responsesByCode[packet.responseCode] = 
          (report.responsesByCode[packet.responseCode] || 0) + 1;
      }
      
      if (packet.destination) {
        report.uniqueHosts.add(packet.destination);
      }
      
      if (packet.method) {
        report.requestsByMethod[packet.method] = 
          (report.requestsByMethod[packet.method] || 0) + 1;
      }
    }

    report.uniqueHosts = Array.from(report.uniqueHosts);
    return report;
  }
}

module.exports = NetworkAnalyzer;
