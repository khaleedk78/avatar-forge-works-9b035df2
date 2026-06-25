import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { toast } from "sonner";

import {
  sceneTemplateService,
  promptTemplateService,
  intensityPresetService,
} from "@/services";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const INTENSITIES = ["SFW", "Edge-of-SFW", "NSFW Teaser", "PPV"] as const;

const SCENE_CATEGORY_OPTIONS = [
  { key: "apartment", label: "Apartment" },
  { key: "kitchen", label: "Kitchen" },
  { key: "living", label: "Living Room" },
  { key: "bedroom", label: "Bedroom" },
  { key: "work", label: "Work" },
  { key: "workplace", label: "Workplace" },
  { key: "secondary", label: "Additional Workspace" },
  { key: "storefront", label: "Storefront" },
] as const;

function slugify(value: string) {
  return value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

// ---------------- New Scene ----------------

export function NewSceneDialog({ characterId }: { characterId?: string }) {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [label, setLabel] = useState("");
  const [category, setCategory] = useState<string>(SCENE_CATEGORY_OPTIONS[0].key);
  const [intensity, setIntensity] = useState<string>("SFW");
  const [description, setDescription] = useState("");
  const [prompt, setPrompt] = useState("");

  const reset = () => {
    setLabel("");
    setCategory(SCENE_CATEGORY_OPTIONS[0].key);
    setIntensity("SFW");
    setDescription("");
    setPrompt("");
  };

  const mutation = useMutation({
    mutationFn: () =>
      sceneTemplateService.create({
        character_id: characterId!,
        category,
        label: label.trim(),
        description: description.trim() || null,
        intensity,
        prompt: prompt.trim(),
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["scene-templates", characterId] });
      toast.success("Scene template added");
      reset();
      setOpen(false);
    },
    onError: (e) => toast.error(e instanceof Error ? e.message : "Failed to add scene"),
  });

  const submit = () => {
    if (!characterId) return toast.error("Lila character not loaded yet");
    if (!label.trim()) return toast.error("Name is required");
    mutation.mutate();
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" disabled={!characterId}>
          <Plus className="mr-2 h-4 w-4" /> New scene
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>New scene template</DialogTitle>
          <DialogDescription>A reusable environment for drops and PPV cycles.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Name</Label>
            <Input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Morning Espresso, Loft Kitchen" />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Category</Label>
              <Select value={category} onValueChange={setCategory}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {SCENE_CATEGORY_OPTIONS.map((c) => (
                    <SelectItem key={c.key} value={c.key}>{c.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Intensity</Label>
              <Select value={intensity} onValueChange={setIntensity}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {INTENSITIES.map((i) => (
                    <SelectItem key={i} value={i}>{i}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-2">
            <Label>Description</Label>
            <Textarea rows={2} value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Short summary of the scene mood." />
          </div>
          <div className="space-y-2">
            <Label>Default prompt</Label>
            <Textarea rows={4} value={prompt} onChange={(e) => setPrompt(e.target.value)} placeholder="Lila in her Boston loft kitchen, warm morning light…" />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={submit} disabled={mutation.isPending}>
            {mutation.isPending ? "Adding…" : "Add scene"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------- New Prompt ----------------

export function NewPromptDialog({ characterId }: { characterId?: string }) {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [intensity, setIntensity] = useState<string>("SFW");
  const [prompt, setPrompt] = useState("");
  const [captionDirection, setCaptionDirection] = useState("");

  const reset = () => {
    setName("");
    setIntensity("SFW");
    setPrompt("");
    setCaptionDirection("");
  };

  const mutation = useMutation({
    mutationFn: () =>
      promptTemplateService.create({
        character_id: characterId!,
        name: name.trim(),
        intensity,
        prompt: prompt.trim(),
        caption_direction: captionDirection.trim() || null,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["prompt-templates", characterId] });
      toast.success("Prompt template added");
      reset();
      setOpen(false);
    },
    onError: (e) => toast.error(e instanceof Error ? e.message : "Failed to add template"),
  });

  const submit = () => {
    if (!characterId) return toast.error("Lila character not loaded yet");
    if (!name.trim()) return toast.error("Name is required");
    mutation.mutate();
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" disabled={!characterId}>
          <Plus className="mr-2 h-4 w-4" /> New template
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>New prompt template</DialogTitle>
          <DialogDescription>A ready-to-fire scaffold for recurring drops.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label>Name</Label>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Morning Home" />
            </div>
            <div className="space-y-2">
              <Label>Intensity</Label>
              <Select value={intensity} onValueChange={setIntensity}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  {INTENSITIES.map((i) => (
                    <SelectItem key={i} value={i}>{i}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-2">
            <Label>Prompt template</Label>
            <Textarea rows={4} value={prompt} onChange={(e) => setPrompt(e.target.value)} placeholder="Lila waking up in her Boston loft, [SCENE_DETAIL], cinematic 35mm…" />
          </div>
          <div className="space-y-2">
            <Label>Caption direction</Label>
            <Textarea rows={2} value={captionDirection} onChange={(e) => setCaptionDirection(e.target.value)} placeholder="Soft, flirty morning energy. Italian phrase + emoji." />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={submit} disabled={mutation.isPending}>
            {mutation.isPending ? "Adding…" : "Add template"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------- New Preset ----------------

export function NewPresetDialog({ characterId }: { characterId?: string }) {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [label, setLabel] = useState("");
  const [promptStyle, setPromptStyle] = useState("");
  const [captionStyle, setCaptionStyle] = useState("");
  const [negativePrompt, setNegativePrompt] = useState("");

  const reset = () => {
    setLabel("");
    setPromptStyle("");
    setCaptionStyle("");
    setNegativePrompt("");
  };

  const mutation = useMutation({
    mutationFn: () =>
      intensityPresetService.create({
        character_id: characterId!,
        key: slugify(label) || `preset-${Date.now()}`,
        label: label.trim(),
        prompt_style: promptStyle.trim() || null,
        caption_style: captionStyle.trim() || null,
        negative_prompt: negativePrompt.trim() || null,
      }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["intensity-presets", characterId] });
      toast.success("Intensity preset added");
      reset();
      setOpen(false);
    },
    onError: (e) => toast.error(e instanceof Error ? e.message : "Failed to add preset"),
  });

  const submit = () => {
    if (!characterId) return toast.error("Lila character not loaded yet");
    if (!label.trim()) return toast.error("Name is required");
    mutation.mutate();
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline" disabled={!characterId}>
          <Plus className="mr-2 h-4 w-4" /> New preset
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>New intensity preset</DialogTitle>
          <DialogDescription>A one-tap tone, prompt, and negative-prompt bundle.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-2">
            <Label>Name</Label>
            <Input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Weekday Edge-of-SFW" />
          </div>
          <div className="space-y-2">
            <Label>Prompt style</Label>
            <Textarea rows={2} value={promptStyle} onChange={(e) => setPromptStyle(e.target.value)} placeholder="Lifestyle, fashion-editorial framing. Suggestive but tasteful." />
          </div>
          <div className="space-y-2">
            <Label>Caption style</Label>
            <Textarea rows={2} value={captionStyle} onChange={(e) => setCaptionStyle(e.target.value)} placeholder="Playful, brand-leaning, Italian phrases, story-led." />
          </div>
          <div className="space-y-2">
            <Label>Negative prompt</Label>
            <Textarea rows={2} value={negativePrompt} onChange={(e) => setNegativePrompt(e.target.value)} placeholder="nudity, explicit, distorted face, extra fingers, watermark…" />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={submit} disabled={mutation.isPending}>
            {mutation.isPending ? "Adding…" : "Add preset"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
