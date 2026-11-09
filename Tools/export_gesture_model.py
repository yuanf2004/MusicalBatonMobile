"""Export Zach's trusted v1 joblib tree and parity fixtures. Requires numpy/joblib/sklearn.
Usage: python3 Tools/export_gesture_model.py /path/to/Zach/MusicalBaton
Only load trusted joblib files. No Python runtime is required by the iOS app.
"""
import csv
import hashlib
import json
from pathlib import Path
import sys
import joblib
import numpy as np

source = Path(sys.argv[1])
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(source / 'tools'))
from train_gesture_model import window_features, feature_names
artifact_path = source / 'models/gesture_v1/gesture_tree.joblib'
artifact = joblib.load(artifact_path)
model = artifact['model']
assert artifact['feature_names'] == feature_names()
tree = model.tree_
nodes = [dict(left=int(tree.children_left[i]), right=int(tree.children_right[i]),
              feature=int(tree.feature[i]), threshold=float(tree.threshold[i]),
              label=str(model.classes_[np.argmax(tree.value[i][0])]))
         for i in range(tree.node_count)]
export = dict(version=1, sourceSHA256=hashlib.sha256(artifact_path.read_bytes()).hexdigest(),
              sourceCommit='ec6c752', windowMS=200, featureNames=feature_names(), nodes=nodes)
(root / 'Musical Baton Mobile/Conducting/gesture_v1.json').write_text(json.dumps(export, separators=(',', ':'))+'\n')
fixtures = []
for session in sorted(source.glob('session-*.csv')):
    with session.open() as f:
        rows = list(csv.DictReader(f))
    axes = ['accel_x_mg','accel_y_mg','accel_z_mg','gyro_x_dps_tenths','gyro_y_dps_tenths','gyro_z_dps_tenths']
    # Exercise full-rate training windows and sparse USB/BLE-size windows.
    for end in np.linspace(100, len(rows)-1, 60, dtype=int):
        for step in (1, 10, 21):
            selected = []
            time = int(rows[end]['device_time_ms'])
            for i in range(end, max(-1, end-100), -step):
                if time-int(rows[i]['device_time_ms']) > 200: break
                selected.append([int(rows[i][a]) for a in axes])
            selected.reverse()
            values = np.asarray(selected, dtype=float)
            features = window_features(values)
            fixtures.append(dict(samples=selected, features=features.tolist(),
                                 label=str(model.predict(features.reshape(1,-1))[0])))
(root / 'Tests/gesture_parity.json').write_text(json.dumps(fixtures, separators=(',', ':'))+'\n')
print(f'Exported {len(nodes)} nodes and {len(fixtures)} parity windows')
