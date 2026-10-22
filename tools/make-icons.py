from PIL import Image
import os
root = os.path.join(os.path.dirname(__file__), '..')
logo = Image.open(os.path.join(root, 'docs', 'brand', 'streplay-logo.png')).convert('RGB')
w, h = logo.size
side = min(w, h)
cx = int(w * 0.53)
left = max(0, min(w - side, cx - side // 2))
icon = logo.crop((left, 0, left + side, side)).resize((256, 256), Image.LANCZOS)
icon.save(os.path.join(root, 'thunderstore', 'icon.png'))

print("icon written")
